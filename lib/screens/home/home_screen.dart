import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shimmer/shimmer.dart';

import 'package:hrms/riverpod_providers.dart';
import 'package:hrms/services/core/auth_service.dart';
import 'package:hrms/services/dashboard/dashboard_chart_service.dart';
import 'package:hrms/services/core/dummy_data.dart';
import 'package:hrms/services/core/error_reporter.dart';
import 'package:hrms/services/core/firestore_service.dart';
import 'package:hrms/services/payroll/payroll_service.dart';
import 'package:hrms/services/core/preferences_service.dart';
import 'package:hrms/core/utils/utils.dart';
import 'package:hrms/widgets/components/custom_timeframe_dropdown.dart';
import 'package:hrms/widgets/dashboard/attendance_line_chart.dart';
import 'package:hrms/widgets/dashboard/holiday_card.dart';
import 'package:hrms/widgets/dashboard/leave_types_pie_chart.dart';
import 'package:hrms/widgets/dashboard/sparkline_card.dart';
import 'package:hrms/widgets/dashboard/top_header.dart';
import 'package:hrms/widgets/dashboard/total_workers_card.dart';
import 'package:hrms/widgets/navigation/notification_sidebar.dart';
import 'package:hrms/widgets/navigation/sidebar_widget.dart';
import 'package:hrms/widgets/components/screen_table_shimmer.dart';
import 'package:hrms/widgets/dialogs/unsaved_changes_dialog.dart';
import 'package:hrms/screens/time_off/assign_time_off.dart';
import 'package:hrms/screens/assets/assets_screen.dart';
import 'package:hrms/screens/attendance/attendance_screen.dart';
import 'package:hrms/screens/documents/documents_screen.dart';
import 'package:hrms/screens/expenses/expenses_screen.dart';
import 'package:hrms/screens/holidays/holidays_screen.dart';
import 'package:hrms/screens/auth/login_screen.dart';
import 'package:hrms/screens/payroll/payroll_screen.dart';
import 'package:hrms/screens/workers/profile_screen.dart';
import 'package:hrms/screens/settings/settings_screen.dart';
import 'package:hrms/screens/time_off/time_off.dart';
import 'package:hrms/screens/workers/workers.dart';
import 'package:hrms/screens/attendance/workers_attendance_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  final int initialSubIndex;

  const HomeScreen({
    super.key,
    this.initialIndex = 0,
    this.initialSubIndex = 0,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late int _selectedIndex;
  late int _selectedSubIndex;

  int _payrollActivationToken = 0;
  String _selectedPeriod = 'This Year';

  bool _showProfile = false;
  bool _showAssignTimeOff = false;
  bool _showNotifications = false;
  bool _showWorkersAttendance = false;

  final List<bool> _activatedScreens = List.filled(13, true);

  final GlobalKey<WorkersScreenState> _workersKey =
      GlobalKey<WorkersScreenState>();
  final GlobalKey<AssignTimeOffScreenState> _assignTimeOffKey =
      GlobalKey<AssignTimeOffScreenState>();
  final GlobalKey<PayrollScreenState> _payrollKey =
      GlobalKey<PayrollScreenState>();

  late final AuthService _authService;
  late final FirestoreService _firestore;

  String _currencyCode = CurrencyUtils.defaultCode;
  bool _isPremium = PreferencesService.cachedIsPremium;
  bool _dashboardReady = false;
  bool _initialized = false;
  bool _workersLoaded = false;
  bool _initialWorkersLoaded = false;
  bool _initialExpensesLoaded = false;
  bool _initialPayrollLoaded = false;
  bool _isGuest = false;
  bool _backToLoginInProgress = false;

  int _totalWorkersCount = 0;
  int _maleWorkersCount = 0;
  int _femaleWorkersCount = 0;
  int _otherWorkersCount = 0;
  double _totalExpensesSum = 0.0;
  double _totalSalarySum = 0.0;

  List<Map<String, dynamic>> _rawExpensesDocs = [];
  List<Map<String, dynamic>> _rawPayrollDocs = [];
  List<Map<String, dynamic>> _workersDocs = [];
  List<DashboardChartPoint> _salaryChartPoints = [];
  List<DashboardChartPoint> _expenseChartPoints = [];
  List<Map<String, dynamic>> _holidays = [];
  List<Map<String, dynamic>> _allAttendanceDocs = [];
  List<Map<String, dynamic>> _allTimeoffDocs = [];
  List<Map<String, dynamic>> _leaveDocs = [];
  List<Map<String, dynamic>> _filteredAttendanceDocs = [];

  Map<String, dynamic>? _selectedTimeOffWorker;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _selectedSubIndex = widget.initialSubIndex;
    final stackIdx = _getStackIndex();
    _activatedScreens[stackIdx] = true;
    _activatedScreens[0] = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);
    _isGuest = _authService.currentUser?.isAnonymous ?? false;

    _restoreProfilePic(_authService.currentUser);
    _loadDashboardData();
    _startPremiumListener();

    if (_isGuest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handlePeriodChanged(_selectedPeriod);
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialProfile());
  }

  int _getStackIndex() {
    if (_showWorkersAttendance) return 11;
    if (_showProfile) return 10;
    if (_showAssignTimeOff) return 9;
    if (_selectedIndex == 0) return 0;
    if (_selectedIndex == 1) return 1;
    if (_selectedIndex == 2) {
      return switch (_selectedSubIndex) {
        0 => 2,
        1 => 3,
        2 => 4,
        3 => 5,
        4 => 6,
        5 => 12,
        _ => 2,
      };
    }
    if (_selectedIndex == 3) return 7;
    if (_selectedIndex == 4) return 8;
    return 0;
  }

  final Map<int, Widget> _cachedScreens = {};

  Widget _getScreen(int index) {
    if (index == 9) {
      return AssignTimeOffScreen(
        key: _assignTimeOffKey,
        onBack: () => setState(() {
          _showAssignTimeOff = false;
          _selectedTimeOffWorker = null;
        }),
        onProfileTap: _openProfile,
        onNotificationTap: _toggleNotifications,
        initialWorker: _selectedTimeOffWorker,
      );
    }
    return _cachedScreens.putIfAbsent(index, () {
      return switch (index) {
        1 => WorkersScreen(
          key: _workersKey,
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        ),
        2 => AttendanceScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
          onWorkersAttendanceTap: () => setState(() {
            _showWorkersAttendance = true;
            _activatedScreens[11] = true;
          }),
        ),
        3 => PayrollScreen(
          key: _payrollKey,
          isActive: true,
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          activationToken: _payrollActivationToken,
          onNotificationTap: _toggleNotifications,
        ),
        4 => TimeOffScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
          onAssignTimeOff: (worker) => _openAssignTimeOff(worker: worker),
        ),
        5 => AssetsScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        ),
        6 => HolidaysScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        ),
        7 => ExpensesScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        ),
        8 => SettingsScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          isGuest: _isGuest,
          onNotificationTap: _toggleNotifications,
        ),
        10 => DocumentsScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        ),
        _ => const SizedBox.shrink(),
      };
    });
  }

  static num _parseAmount(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value;
    if (value is String) {
      return double.tryParse(value.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
    }
    return 0;
  }

  static double _parseNumToDouble(dynamic value) =>
      _parseAmount(value).toDouble();

  Future<void> _loadInitialProfile() async {
    final user = _authService.currentUser;
    if (user == null || user.isAnonymous) return;

    Map<String, dynamic>? profile;
    try {
      profile = await _firestore.getUserProfileOrThrow();
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'loadInitialProfile');
      return;
    }

    if (!mounted) return;

    if (profile == null) {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
      return;
    }

    final profilePic = profile['profilePic']?.toString().trim() ?? '';
    AuthService.profilePicNotifier.value = profilePic.isEmpty
        ? null
        : profilePic;

    final isPremium = profile['isPremium'] == true;
    final currencyCode = CurrencyUtils.normalize(profile['currency']);
    await PreferencesService.setPremium(isPremium);

    if (mounted && (_isPremium != isPremium || _currencyCode != currencyCode)) {
      setState(() {
        _isPremium = isPremium;
        _currencyCode = currencyCode;
      });
    }
  }

  Future<void> _restoreProfilePic(User? currentUser) async {
    if (currentUser != null && !currentUser.isAnonymous) return;

    final cachedUrl = PreferencesService.cachedProfilePicUrl;
    AuthService.profilePicNotifier.value =
        (cachedUrl != null && cachedUrl.isNotEmpty) ? cachedUrl : null;
  }

  void _startPremiumListener() {
    final user = _authService.currentUser;
    if (user == null || user.isAnonymous) return;

    ref.listenAsync(
      userProfileProvider,
      (profile) async {
        if (profile == null) {
          try {
            await _authService.signOut();
          } catch (_) {}
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          }
          return;
        }

        final isPremium = profile['isPremium'] == true;
        final currencyCode = CurrencyUtils.normalize(profile['currency']);
        final profilePic = profile['profilePic']?.toString().trim() ?? '';
        final companyStamp =
            profile['companyStampUrl']?.toString().trim() ?? '';

        AuthService.profilePicNotifier.value = profilePic.isEmpty
            ? null
            : profilePic;
        AuthService.companyStampNotifier.value = companyStamp.isEmpty
            ? null
            : companyStamp;

        await PreferencesService.setPremium(isPremium);

        if (mounted &&
            (_isPremium != isPremium || _currencyCode != currencyCode)) {
          setState(() {
            _isPremium = isPremium;
            _currencyCode = currencyCode;
          });
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        ErrorReporter.report(
          error,
          stackTrace,
          context: 'premiumProfileStream',
        );
      },
    );
  }

  void _loadDashboardData() {
    if (_isGuest) {
      _loadGuestDashboardData();
    } else {
      _loadFirestoreDashboardData();
    }
  }

  void _loadGuestDashboardData() {
    setState(() {
      final workers = DummyData.workers;
      _totalWorkersCount = workers.length;

      int mCount = 0, fCount = 0, oCount = 0;
      for (final w in workers) {
        final gender = (w['gender'] ?? '').toString().trim().toLowerCase();
        if (gender == 'female') {
          fCount++;
        } else if (gender == 'male') {
          mCount++;
        } else if (gender == 'other' || gender == 'others') {
          oCount++;
        }
      }
      _maleWorkersCount = mCount;
      _femaleWorkersCount = fCount;
      _otherWorkersCount = oCount;
      _allTimeoffDocs = List<Map<String, dynamic>>.from(DummyData.timeoff);

      _holidays = _buildGuestHolidays();
      _allAttendanceDocs = _buildEnrichedGuestAttendance();
      _workersDocs = List<Map<String, dynamic>>.from(DummyData.workers);
      _rawPayrollDocs = List<Map<String, dynamic>>.from(DummyData.payroll);
      _workersLoaded = true;
      _initialWorkersLoaded = true;
      _initialExpensesLoaded = true;
      _initialPayrollLoaded = true;
    });
    _maybeMarkDashboardReady();
  }

  void _maybeMarkDashboardReady() {
    if (_dashboardReady) return;
    if (!_initialWorkersLoaded ||
        !_initialExpensesLoaded ||
        !_initialPayrollLoaded) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _recalculateLeaveAndAttendanceCharts();
      if (_isGuest) {
        _recalculateDummyTotals(_selectedPeriod);
      } else {
        _recalculateSumsForPeriod(_selectedPeriod);
      }
      _dashboardReady = true;
    });
  }

  List<Map<String, dynamic>> _buildGuestHolidays() {
    const monthNames = LocalizationHelper.englishMonthNames;
    const weekDays = LocalizationHelper.englishWeekdayNames;

    return DummyData.holidays.values
        .expand((list) => list)
        .cast<Map<String, dynamic>>()
        .map((h) {
          final parts = (h['date'] ?? '').toString().split('/');
          String day = '', month = '', dayOfWeek = '';

          if (parts.length == 3) {
            final dayNum = int.tryParse(parts[0]) ?? 0;
            final monthNum = int.tryParse(parts[1]) ?? 0;
            final year = int.tryParse(parts[2]) ?? DateTime.now().year;
            day = dayNum.toString();
            month = monthNum >= 1 && monthNum <= 12 ? monthNames[monthNum] : '';
            if (monthNum >= 1 &&
                monthNum <= 12 &&
                dayNum >= 1 &&
                dayNum <= 31) {
              dayOfWeek =
                  weekDays[DateTime(year, monthNum, dayNum).weekday % 7];
            }
          }

          return {
            'name': h['name'] ?? '',
            'day': day,
            'month': month,
            'dayOfWeek': dayOfWeek,
            'isEnabled': true,
            'remainingDays': '0',
          };
        })
        .toList();
  }

  List<Map<String, dynamic>> _buildEnrichedGuestAttendance() {
    return DummyData.attendance.map((att) {
      final status = (att['status'] ?? '').toString().trim().toLowerCase();
      if (status == 'leave') {
        final reason = (att['reason'] ?? '').toString().trim().toLowerCase();
        final type = switch (reason) {
          'vacation' => 'Casual Leave',
          'medical' => 'Medical Leave',
          'sick' => 'Sick Leave',
          _ => 'Annual Leave',
        };
        return {...att, 'type': type};
      }
      return att;
    }).toList();
  }

  void _loadFirestoreDashboardData() {
    setState(() => _holidays = []);

    ref.listenAsync(holidaysProvider, (records) {
      if (!mounted) return;
      setState(() {
        _holidays = records
            .where((h) => h['type'] != 'company_work_days')
            .toList();
      });
    });

    ref.listenAsync(workersProvider, (records) {
      if (!mounted) return;

      int mCount = 0, fCount = 0, oCount = 0, activeHeadcount = 0;
      final today = DateTime.now();
      final list = <Map<String, dynamic>>[];

      for (final data in records) {
        list.add(data);

        if (!PayrollService.isWorkerEligibleForPayroll(data)) continue;

        final joiningDate = AppDateUtils.dateFromValue(
          data['joiningDate'] ?? data['dateOfJoining'],
        );
        if (joiningDate != null) {
          final normJoining = DateTime(
            joiningDate.year,
            joiningDate.month,
            joiningDate.day,
          );
          final normToday = DateTime(today.year, today.month, today.day);
          if (normJoining.isAfter(normToday)) continue;
        }

        activeHeadcount++;
        final gender = (data['gender'] ?? '').toString().trim().toLowerCase();
        if (gender == 'female') {
          fCount++;
        } else if (gender == 'male') {
          mCount++;
        } else if (gender == 'other' || gender == 'others') {
          oCount++;
        }
      }

      setState(() {
        _totalWorkersCount = activeHeadcount;
        _maleWorkersCount = mCount;
        _femaleWorkersCount = fCount;
        _otherWorkersCount = oCount;
        _workersDocs = list;
        _workersLoaded = true;
        _recalculateLeaveAndAttendanceCharts();
        if (_initialWorkersLoaded &&
            _initialExpensesLoaded &&
            _initialPayrollLoaded) {
          _recalculateSumsForPeriod(_selectedPeriod);
        }
      });
      _initialWorkersLoaded = true;
      _maybeMarkDashboardReady();
    });

    ref.listenAsync(attendanceProvider, (records) {
      if (!mounted) return;
      setState(() {
        _allAttendanceDocs = records;
        _recalculateLeaveAndAttendanceCharts();
      });
    });

    ref.listenAsync(timeOffProvider, (records) {
      if (!mounted) return;
      setState(() {
        _allTimeoffDocs = records;
        _recalculateLeaveAndAttendanceCharts();
      });
    });

    ref.listenAsync(expensesProvider, (records) {
      if (!mounted) return;
      setState(() {
        _rawExpensesDocs = records.map((data) {
          return {...data, 'amount': _parseAmount(data['amount'])};
        }).toList();
        if (_initialWorkersLoaded &&
            _initialExpensesLoaded &&
            _initialPayrollLoaded) {
          _recalculateSumsForPeriod(_selectedPeriod);
        }
      });
      _initialExpensesLoaded = true;
      _maybeMarkDashboardReady();
    });

    ref.listenAsync(payrollProvider, (records) {
      if (!mounted) return;
      setState(() {
        _rawPayrollDocs = records.map((data) {
          final netSalary = _resolvePayrollNetSalary(data);
          return {...data, 'netSalary': netSalary};
        }).toList();
        if (_initialWorkersLoaded &&
            _initialExpensesLoaded &&
            _initialPayrollLoaded) {
          _recalculateSumsForPeriod(_selectedPeriod);
        }
      });
      _initialPayrollLoaded = true;
      _maybeMarkDashboardReady();
    });
  }

  double _resolvePayrollNetSalary(Map<String, dynamic>? data) {
    final savedNet = data?['netSalaryAmount'];
    if (savedNet is num) return savedNet.toDouble();

    final legacyFormatted = (data?['netSalary'] ?? '').toString().trim();
    if (legacyFormatted.isNotEmpty) {
      return PayrollService.extractSalary(legacyFormatted);
    }

    return (PayrollService.calculatePayroll(
              salary: (data?['salary'] ?? '').toString(),
              totalWorkDays: (data?['totalWorkDays'] ?? '').toString(),
              absents: (data?['absents'] ?? '').toString(),
              leaves: (data?['leaves'] ?? '').toString(),
              overtimeAmount: (data?['overtimeAmount'] ?? '').toString(),
              absentDeductionPerDay: data?['deductionsAreTotals'] == true
                  ? ''
                  : (data?['absentDeduction'] ?? '').toString(),
              leaveDeductionPerDay: data?['deductionsAreTotals'] == true
                  ? ''
                  : (data?['leaveDeduction'] ?? '').toString(),
              salaryType: (data?['salaryType'] ?? 'Monthly').toString(),
            )['netSalary']
            as num)
        .toDouble();
  }

  void _handlePeriodChanged(String period) {
    setState(() {
      _selectedPeriod = period;
      _recalculateLeaveAndAttendanceCharts();
      if (_isGuest) {
        _recalculateDummyTotals(period);
      } else {
        _recalculateSumsForPeriod(period);
      }
    });
  }

  void _recalculateLeaveAndAttendanceCharts() {
    final isEffectivelyGuest = _isGuest || PreferencesService.cachedIsGuest;
    _leaveDocs = DashboardChartService.mergedLeaveDaysForPeriod(
      timeOffRecords: _allTimeoffDocs,
      attendanceRecords: isEffectivelyGuest
          ? const <Map<String, dynamic>>[]
          : _allAttendanceDocs
                .where(_attendanceBelongsToExistingWorker)
                .toList(),
      period: _selectedPeriod,
      workers: _workersDocs,
    );
    _filteredAttendanceDocs = _getFilteredAttendanceDocs();
  }

  void _recalculateSumsForPeriod(String period) {
    final paidPayroll = PayrollService.paidPayrollRecordsForActiveWorkers(
      _workersDocs,
      _rawPayrollDocs,
    );
    final paidKeys = paidPayroll
        .map((r) => (r['payrollKey'] ?? '').toString().trim())
        .where((k) => k.isNotEmpty)
        .toSet();

    final payrollAmountByKey = <String, double>{};
    for (final record in paidPayroll) {
      final key = (record['payrollKey'] ?? '').toString().trim();
      if (key.isEmpty) continue;
      final net = _parseNumToDouble(record['netSalary']);
      if (net > 0) payrollAmountByKey[key] = net;
    }

    final activeExpenses = _rawExpensesDocs.where((r) {
      final category = (r['category'] ?? '').toString().trim().toLowerCase();
      final payrollKey = (r['payrollKey'] ?? '').toString().trim();
      if (category != 'salary' || payrollKey.isEmpty) return true;
      return paidKeys.contains(payrollKey);
    }).toList();

    double expenseValueOf(Map<String, dynamic> r) {
      final category = (r['category'] ?? '').toString().trim().toLowerCase();
      final payrollKey = (r['payrollKey'] ?? '').toString().trim();
      if (category == 'salary' && payrollKey.isNotEmpty) {
        return payrollAmountByKey[payrollKey] ?? 0.0;
      }
      return _parseNumToDouble(r['amount']);
    }

    final expenseSeries = DashboardChartService.buildSeries(
      records: activeExpenses,
      valueOf: expenseValueOf,
      period: period,
      dateOf: DashboardChartService.expenseRecordDate,
    );

    final salaryExpenses = activeExpenses
        .where(
          (r) =>
              (r['category'] ?? '').toString().trim().toLowerCase() == 'salary',
        )
        .toList();
    final salarySeries = DashboardChartService.buildSeries(
      records: salaryExpenses,
      valueOf: (r) {
        final key = (r['payrollKey'] ?? '').toString().trim();
        return key.isNotEmpty
            ? payrollAmountByKey[key] ?? 0.0
            : _parseNumToDouble(r['amount']);
      },
      period: period,
      dateOf: DashboardChartService.expenseRecordDate,
    );

    _expenseChartPoints = expenseSeries.points;
    _salaryChartPoints = salarySeries.points;
    _totalExpensesSum = expenseSeries.total;
    _totalSalarySum = salarySeries.total;
  }

  void _recalculateDummyTotals(String period) {
    final activePayroll =
        PayrollService.paidPayrollRecordsForActiveWorkers(
          DummyData.workers,
          DummyData.payroll,
        ).map((item) {
          final savedNet = item['netSalaryAmount'];
          final formattedNet = (item['netSalary'] ?? '').toString();
          final amount = item['amount'];
          final netSalary = savedNet is num
              ? savedNet.toDouble()
              : formattedNet.trim().isNotEmpty
              ? PayrollService.extractSalary(formattedNet)
              : amount is num
              ? amount.toDouble()
              : 0.0;
          return {...item, 'netSalary': netSalary};
        }).toList();

    final payrollAmountByKey = <String, double>{};
    for (final record in activePayroll) {
      final key = (record['payrollKey'] ?? '').toString().trim();
      if (key.isEmpty) continue;
      final net = _parseNumToDouble(record['netSalary']);
      if (net > 0) payrollAmountByKey[key] = net;
    }

    final now = DateTime.now();
    final maxDays = switch (period) {
      'Today' => 0,
      'Week' || 'This Week' => 7,
      'Month' || 'This Month' => 30,
      '6 Month' || 'Last 6 Months' => 180,
      _ => 365,
    };

    final adjustedExpenses = DummyData.expenses.asMap().entries.map((entry) {
      final record = Map<String, dynamic>.from(entry.value);
      final daysAgo = (entry.key * (maxDays + 1) / DummyData.expenses.length)
          .floor();
      final newDate = now.subtract(Duration(days: daysAgo));
      record['date'] =
          '${newDate.day.toString().padLeft(2, '0')}/${newDate.month.toString().padLeft(2, '0')}/${newDate.year}';
      return record;
    }).toList();

    final filteredExpenses = adjustedExpenses.where((r) {
      final category = (r['category'] ?? '').toString().trim().toLowerCase();
      final payrollKey = (r['payrollKey'] ?? '').toString().trim();
      if (category == 'salary' && payrollKey.isNotEmpty) {
        return payrollAmountByKey.containsKey(payrollKey);
      }
      return true;
    }).toList();

    double expenseValueOf(Map<String, dynamic> r) {
      final category = (r['category'] ?? '').toString().trim().toLowerCase();
      final payrollKey = (r['payrollKey'] ?? '').toString().trim();
      if (category == 'salary' && payrollKey.isNotEmpty) {
        return payrollAmountByKey[payrollKey] ?? 0.0;
      }
      return _parseNumToDouble(r['amount']);
    }

    final expenseSeries = DashboardChartService.buildSeries(
      records: filteredExpenses,
      valueOf: expenseValueOf,
      period: period,
      dateOf: DashboardChartService.expenseRecordDate,
      placeUndatedInCurrentPeriod: true,
    );

    final salaryExpenses = filteredExpenses
        .where(
          (r) =>
              (r['category'] ?? '').toString().trim().toLowerCase() == 'salary',
        )
        .toList();
    final salarySeries = DashboardChartService.buildSeries(
      records: salaryExpenses,
      valueOf: (r) {
        final key = (r['payrollKey'] ?? '').toString().trim();
        return key.isNotEmpty
            ? payrollAmountByKey[key] ?? 0.0
            : _parseNumToDouble(r['amount']);
      },
      period: period,
      dateOf: DashboardChartService.expenseRecordDate,
      placeUndatedInCurrentPeriod: true,
    );

    _expenseChartPoints = expenseSeries.points;
    _salaryChartPoints = salarySeries.points;
    _totalExpensesSum = expenseSeries.total;
    _totalSalarySum = salarySeries.total;
  }

  Set<String> get _existingWorkerIds {
    return _workersDocs
        .map((w) => (w['id'] ?? w['workerId'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  bool _attendanceBelongsToExistingWorker(Map<String, dynamic> attendance) {
    if (_isGuest) return true;
    if (!_workersLoaded) return true;
    if (_workersDocs.isEmpty) return false;

    final workerId = (attendance['workerId'] ?? '').toString().trim();
    if (workerId.isNotEmpty) return _existingWorkerIds.contains(workerId);

    final email = (attendance['email'] ?? '').toString().trim().toLowerCase();
    if (email.isNotEmpty) {
      return _workersDocs.any(
        (w) => (w['email'] ?? '').toString().trim().toLowerCase() == email,
      );
    }

    final name = (attendance['name'] ?? attendance['workerName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (name.isEmpty) return false;
    return _workersDocs.any(
      (w) => (w['name'] ?? '').toString().trim().toLowerCase() == name,
    );
  }

  List<Map<String, dynamic>> _getFilteredAttendanceDocs() {
    final rawDocs = _isGuest ? DummyData.attendance : _allAttendanceDocs;
    final periodDocs = attendanceRecordsForPeriod(rawDocs, _selectedPeriod);
    if (_isGuest || !_workersLoaded || _workersDocs.isEmpty) return periodDocs;

    return latestAttendanceRecordPerWorker(
      periodDocs,
      period: _selectedPeriod,
      workerIdResolver: _dashboardAttendanceWorkerId,
    );
  }

  String? _dashboardAttendanceWorkerId(Map<String, dynamic> attendance) {
    final rawWorkerId = (attendance['workerId'] ?? '').toString().trim();
    if (rawWorkerId.isNotEmpty && _existingWorkerIds.contains(rawWorkerId)) {
      return rawWorkerId;
    }

    final email = (attendance['email'] ?? '').toString().trim().toLowerCase();
    final name = (attendance['name'] ?? attendance['workerName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    for (final worker in _workersDocs) {
      final workerId = (worker['id'] ?? worker['workerId'] ?? '')
          .toString()
          .trim();
      if (email.isNotEmpty &&
          (worker['email'] ?? '').toString().trim().toLowerCase() == email) {
        return workerId;
      }
      if (name.isNotEmpty &&
          (worker['name'] ?? '').toString().trim().toLowerCase() == name) {
        return workerId;
      }
    }
    return null;
  }

  String _formatCompactCurrency(double amount, {bool clampToZero = false}) {
    final value = clampToZero
        ? amount.clamp(0, double.infinity).toDouble()
        : amount;
    final symbol = CurrencyUtils.symbolFor(_currencyCode);

    if (value.abs() >= 1e3) {
      return CurrencyUtils.formatCompactLocale(
        value,
        context.locale.toString(),
        symbol: symbol,
      );
    }

    final separator = symbol.length > 1 ? ' ' : '';
    try {
      return '$symbol$separator${NumberFormat.currency(locale: context.locale.toString(), symbol: '', decimalDigits: 2).format(value)}';
    } catch (_) {
      return '$symbol$separator${NumberFormat.currency(locale: 'en_US', symbol: '', decimalDigits: 2).format(value)}';
    }
  }

  bool _holidayFallsWithinSelectedPeriod(int daysUntil) {
    return switch (_selectedPeriod) {
      'Today' => daysUntil == 0,
      'Week' || 'This Week' => daysUntil <= 7,
      'Month' || 'This Month' => daysUntil <= 30,
      '6 Month' || 'Last 6 Months' => daysUntil <= 180,
      'This Year' => daysUntil <= 365,
      _ => true,
    };
  }

  void _handleLogout() => showLogoutDialog(context);

  Future<void> _handleBackToLogin() async {
    if (_backToLoginInProgress) return;
    _backToLoginInProgress = true;
    setState(() => _isGuest = true);
    try {
      await _authService.signOut(preserveBiometricLogin: true);
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'backToLoginSignOut');
    } finally {
      _backToLoginInProgress = false;
    }
  }

  Future<void> _openProfile() async {
    if (_showAssignTimeOff &&
        (_assignTimeOffKey.currentState?.hasUnsavedChanges ?? false)) {
      final shouldDiscard = await UnsavedChangesDialog.show(context);
      if (!shouldDiscard) return;
    }
    setState(() {
      _showProfile = true;
      _showWorkersAttendance = false;
      _showAssignTimeOff = false;
      _showNotifications = false;
      _selectedTimeOffWorker = null;
      _activatedScreens[10] = true;
    });
  }

  void _toggleNotifications() =>
      setState(() => _showNotifications = !_showNotifications);

  void _openAssignTimeOff({Map<String, dynamic>? worker}) {
    setState(() {
      _showProfile = false;
      _showWorkersAttendance = false;
      _showNotifications = false;
      _showAssignTimeOff = true;
      _selectedTimeOffWorker = worker;
      _activatedScreens[9] = true;
    });
  }

  void _handleNotificationNavigation(String type) {
    setState(() {
      _showNotifications = false;
      switch (type) {
        case 'worker_added':
          _selectedIndex = 1;
        case 'attendance_marked':
          _selectedIndex = 2;
          _selectedSubIndex = 0;
        case 'payroll_added' || 'payroll_due':
          _selectedIndex = 2;
          _selectedSubIndex = 1;
        case 'time_off_added':
          _selectedIndex = 2;
          _selectedSubIndex = 2;
        case 'asset_added':
          _selectedIndex = 2;
          _selectedSubIndex = 3;
        case 'holiday_added':
          _selectedIndex = 2;
          _selectedSubIndex = 4;
        case 'expense_added':
          _selectedIndex = 3;
      }
      _showProfile = false;
      _showWorkersAttendance = false;
      _showAssignTimeOff = false;
      _selectedTimeOffWorker = null;
      _activatedScreens[_getStackIndex()] = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: LayoutBuilder(
        builder: (context, constraints) {
          const double minWidth = 1200;
          final bodyWidth = constraints.maxWidth < minWidth
              ? minWidth
              : constraints.maxWidth;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: bodyWidth,
              height: constraints.maxHeight,
              child: Row(
                children: [
                  SidebarWidget(
                    key: ValueKey('sidebar_${context.locale.languageCode}'),
                    selectedIndex: _showProfile ? -1 : _selectedIndex,
                    selectedSubIndex: _selectedSubIndex,
                    isGuest: _isGuest,
                    isPremium: _isPremium,
                    onItemSelected: (index, {subIndex}) async {
                      if (_selectedIndex == 1 &&
                          _workersKey.currentState?.hasUnsavedChanges == true) {
                        final shouldDiscard = await _workersKey.currentState!
                            .confirmDiscardChanges();
                        if (!shouldDiscard) return;
                      }

                      if (_selectedIndex == 1) {
                        _workersKey.currentState?.closeIdleBulkAddFlow();
                      }

                      if (_showAssignTimeOff) {
                        if (!context.mounted) return;
                        final shouldDiscard = await UnsavedChangesDialog.show(
                          context,
                        );
                        if (!shouldDiscard) return;
                      }

                      if (!context.mounted) return;

                      setState(() {
                        final targetSubIndex = subIndex ?? _selectedSubIndex;
                        if (index == 2 && targetSubIndex == 1) {
                          _payrollActivationToken++;
                        }
                        _selectedIndex = index;
                        if (subIndex != null) _selectedSubIndex = subIndex;
                        _showProfile = false;
                        _showWorkersAttendance = false;
                        _showAssignTimeOff = false;
                        _showNotifications = false;
                        _selectedTimeOffWorker = null;
                        _activatedScreens[_getStackIndex()] = true;
                      });

                      if (index == 2 && (subIndex == 1 || (subIndex == null && _selectedSubIndex == 1))) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _payrollKey.currentState?.onSidebarPayrollClicked();
                        });
                      }
                    },
                    onBackToLogin: _handleBackToLogin,
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Builder(
                          builder: (context) {
                            final stackIndex = _getStackIndex();
                            return IndexedStack(
                              index: stackIndex,
                              children: [
                                TickerMode(
                                  enabled: stackIndex == 0,
                                  child: _activatedScreens[0]
                                      ? (_dashboardReady
                                            ? _buildDashboardView()
                                            : _buildDashboardLoadingView())
                                      : const SizedBox.shrink(),
                                ),

                                for (int i = 1; i <= 9; i++)
                                  TickerMode(
                                    enabled: stackIndex == i,
                                    child: _activatedScreens[i]
                                        ? _getScreen(i)
                                        : const SizedBox.shrink(),
                                  ),

                                TickerMode(
                                  enabled: stackIndex == 10,
                                  child: _activatedScreens[10]
                                      ? _buildProfileView(stackIndex == 10)
                                      : const SizedBox.shrink(),
                                ),

                                TickerMode(
                                  enabled: stackIndex == 11,
                                  child: _activatedScreens[11]
                                      ? WorkersAttendanceScreen(
                                          hideSidebar: true,
                                          onProfileTap: _openProfile,
                                          onBack: () => setState(
                                            () => _showWorkersAttendance = false,
                                          ),
                                          onNotificationTap: _toggleNotifications,
                                        )
                                      : const SizedBox.shrink(),
                                ),

                                TickerMode(
                                  enabled: stackIndex == 12,
                                  child: _activatedScreens[12]
                                      ? _getScreen(10)
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            );
                          },
                        ),
                        if (_showNotifications) ...[
                          Positioned.fill(
                            child: GestureDetector(
                              onTap: _toggleNotifications,
                              behavior: HitTestBehavior.opaque,
                            ),
                          ),
                          NotificationSidebar(
                            key: ValueKey(
                              'notif_sidebar_${context.locale.languageCode}',
                            ),
                            onClose: _toggleNotifications,
                            onNotificationTap: _handleNotificationNavigation,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDashboardLoadingView() {
    final unreadCount = _isGuest
        ? DummyData.notifications.where((n) => n['isRead'] != true).length
        : ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;
    return Column(
      children: [
        TopHeader(
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
          unreadCount: unreadCount,
        ),
        Expanded(
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: DelayedShimmer(
                child: Shimmer.fromColors(
                  baseColor: screenShimmerBaseColor,
                  highlightColor: screenShimmerHighlightColor,
                  period: screenShimmerPeriod,
                  direction: ShimmerDirection.ltr,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _DashboardShimmerBlock(width: 145, height: 28),
                            _DashboardShimmerBlock(
                              width: 140,
                              height: 44,
                              radius: 6,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 220,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _buildSummaryShimmerCard()),
                              const SizedBox(width: 6),
                              Expanded(child: _buildSummaryShimmerCard()),
                              const SizedBox(width: 6),
                              Expanded(child: _buildSummaryShimmerCard()),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Row(
                          children: [
                            Expanded(
                              child: _DashboardShimmerBlock(
                                width: 205,
                                height: 24,
                              ),
                            ),
                            SizedBox(width: 6),
                            Expanded(
                              child: _DashboardShimmerBlock(
                                width: 135,
                                height: 24,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 330,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _buildChartShimmerCard()),
                              const SizedBox(width: 6),
                              Expanded(child: _buildChartShimmerCard()),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const _DashboardShimmerBlock(width: 190, height: 24),
                        const SizedBox(height: 24),
                        _buildHolidayShimmerCard(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryShimmerCard() {
    return _dashboardSkeletonCard(
      padding: const EdgeInsets.all(20),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DashboardShimmerBlock(width: 40, height: 40, radius: 8),
              SizedBox(width: 14),
              Expanded(child: _DashboardShimmerBlock(width: 130, height: 20)),
              SizedBox(width: 20),
              _DashboardShimmerBlock(width: 72, height: 22),
            ],
          ),
          Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _DashboardShimmerBlock(width: 105, height: 105, radius: 53),
              SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _DashboardShimmerBlock(height: 12),
                    SizedBox(height: 14),
                    _DashboardShimmerBlock(height: 12),
                    SizedBox(height: 14),
                    _DashboardShimmerBlock(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartShimmerCard() {
    return _dashboardSkeletonCard(
      padding: const EdgeInsets.all(24),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DashboardShimmerBlock(width: 92, height: 18),
          Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _DashboardShimmerBlock(width: 36, height: 90, radius: 4),
              SizedBox(width: 18),
              _DashboardShimmerBlock(width: 36, height: 145, radius: 4),
              SizedBox(width: 18),
              _DashboardShimmerBlock(width: 36, height: 110, radius: 4),
              SizedBox(width: 18),
              Expanded(child: _DashboardShimmerBlock(height: 2, radius: 1)),
            ],
          ),
          SizedBox(height: 22),
          _DashboardShimmerBlock(height: 2, radius: 1),
        ],
      ),
    );
  }

  Widget _buildHolidayShimmerCard() {
    return _dashboardSkeletonCard(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DashboardShimmerBlock(width: 105, height: 20),
          const SizedBox(height: 30),
          Row(
            children: List.generate(5, (index) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 4 ? 0 : 16),
                  child: const _DashboardShimmerBlock(height: 78, radius: 6),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _dashboardSkeletonCard({
    required Widget child,
    required EdgeInsets padding,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFF0F1F4)),
      ),
      child: child,
    );
  }

  Widget _buildDashboardView() {
    final unreadCount = _isGuest
        ? DummyData.notifications.where((n) => n['isRead'] != true).length
        : ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;

    return Column(
      children: [
        TopHeader(
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
          unreadCount: unreadCount,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 40.0,
              vertical: 24.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'dashboard'.tr(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF000000),
                      ),
                    ),
                    CustomTimeframeDropdown(
                      selectedPeriod: _selectedPeriod,
                      options: const [
                        'Today',
                        'This Week',
                        'This Month',
                        'Last 6 Months',
                        'This Year',
                      ],
                      onChanged: _handlePeriodChanged,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 220,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: TotalWorkersCard(
                          count: _totalWorkersCount,
                          maleCount: _maleWorkersCount,
                          femaleCount: _femaleWorkersCount,
                          otherCount: _otherWorkersCount,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SparklineCard(
                          title: 'salary_paid'.tr(),
                          amount: _formatCompactCurrency(
                            _totalSalarySum,
                            clampToZero: true,
                          ),
                          rawValue: _totalSalarySum,
                          points: _salaryChartPoints,
                          period: _selectedPeriod,
                          lineColor: const Color(0xFF4C84E0),
                          currencySymbol: CurrencyUtils.symbolFor(
                            _currencyCode,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SparklineCard(
                          title: 'total_expenses'.tr(),
                          amount: _formatCompactCurrency(_totalExpensesSum),
                          rawValue: _totalExpensesSum,
                          points: _expenseChartPoints,
                          period: _selectedPeriod,
                          lineColor: const Color(0xFF0EA5E9),
                          currencySymbol: CurrencyUtils.symbolFor(
                            _currencyCode,
                          ),
                          tooltipDecimalDigits: 3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Text(
                        'attendance_overview'.tr(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 1,
                      child: Text(
                        'leave_types'.tr(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Builder(
                  builder: (context) {
                    final leaveDocs = _leaveDocs;
                    final filteredAttendance = _filteredAttendanceDocs;

                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 1,
                            child: AttendanceLineChart(
                              period: _selectedPeriod,
                              isEmpty: filteredAttendance.isEmpty,
                              attendanceDocs: filteredAttendance,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 1,
                            child: LeaveTypesPieChart(
                              period: _selectedPeriod,
                              isEmpty:
                                  leaveDocs.isEmpty || _totalWorkersCount == 0,
                              leaveDocs: leaveDocs,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'upcoming_holidays'.tr(),
                  style: const TextStyle(
                    color: Color(0xFF000000),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 24),
                _buildHolidaysCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHolidaysCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.45),
            blurRadius: 12,
            spreadRadius: 1.5,
          ),
        ],
      ),
      child: Builder(
        builder: (context) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final groupedHolidays = _buildGroupedHolidays(now, today);

          if (groupedHolidays.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/holidays_icon.svg',
                      height: 50,
                      width: 50,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF9CA3AF),
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'no_holidays_yet'.tr(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'overview'.tr(),
                style: const TextStyle(
                  color: Color(0xFF000000),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 40),
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 16.0;
                  final itemWidth = (constraints.maxWidth - (spacing * 4)) / 5;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: groupedHolidays.map((h) {
                      final remainingDays =
                          int.tryParse((h['remainingDays'] ?? '').toString()) ??
                          -1;
                      return SizedBox(
                        width: itemWidth,
                        child: HolidayCard(
                          day: h['day'] != null
                              ? '${h['day']}'.padLeft(2, '0')
                              : '',
                          month: h['month'] ?? 'May',
                          remainingDays: h['remainingDays'] ?? '',
                          dayOfWeek: h['dayOfWeek'] ?? '',
                          holidayNames:
                              (h['holidayNamesList'] as List<String>?) ??
                              [(h['name'] ?? '').toString()],
                          isActive: remainingDays >= 0 && remainingDays <= 5,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _buildGroupedHolidays(
    DateTime now,
    DateTime today,
  ) {
    final activeHolidays = <Map<String, dynamic>>[];

    for (final source in _holidays) {
      if (source['isEnabled'] == false) continue;

      final holidayDate = _isGuest
          ? _guestHolidayDateForDisplay(source, now)
          : _holidayDateForDisplay(source, today);
      if (holidayDate == null) continue;

      final daysUntil = holidayDate.difference(_isGuest ? now : today).inDays;
      if (daysUntil < 0 || !_holidayFallsWithinSelectedPeriod(daysUntil)) {
        continue;
      }

      final holiday = Map<String, dynamic>.from(source);
      holiday['day'] = holidayDate.day;
      holiday['month'] = DateFormat('MMMM', 'en_US').format(holidayDate);
      holiday['remainingDays'] = daysUntil.toString();
      holiday['dayOfWeek'] = DateFormat(
        'EEEE',
        context.locale.toString(),
      ).format(holidayDate);
      activeHolidays.add(holiday);
    }

    activeHolidays.sort((a, b) {
      final aDays = int.tryParse(a['remainingDays']?.toString() ?? '') ?? 9999;
      final bDays = int.tryParse(b['remainingDays']?.toString() ?? '') ?? 9999;
      return aDays.compareTo(bDays);
    });

    final grouped = <Map<String, dynamic>>[];
    for (final h in activeHolidays) {
      final key = '${h['day']}_${h['month']}';
      final existing = grouped.cast<Map<String, dynamic>?>().firstWhere(
        (g) => '${g!['day']}_${g['month']}' == key,
        orElse: () => null,
      );
      if (existing != null) {
        final names = (existing['holidayNamesList'] ?? <String>[]) as List;
        final newName = (h['name'] ?? '').toString();
        if (!names.contains(newName)) names.add(newName);
        existing['holidayNamesList'] = names;
      } else {
        final g = Map<String, dynamic>.from(h);
        g['holidayNamesList'] = <String>[(h['name'] ?? '').toString()];
        grouped.add(g);
      }
    }

    return grouped;
  }

  Widget _buildProfileView(bool isActive) {
    return Column(
      children: [
        ProfileInlineHeader(
          onLogout: _handleLogout,
          onNotificationTap: _toggleNotifications,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40.0, 16.0, 40.0, 30.0),
            child: ProfileBody(isActive: isActive),
          ),
        ),
      ],
    );
  }
}

class _DashboardShimmerBlock extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const _DashboardShimmerBlock({
    this.width,
    required this.height,
    this.radius = 5,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

int? _intValue(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString().trim());
}

DateTime? _validHolidayDate(int year, int month, int day) {
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

DateTime? _guestHolidayDateForDisplay(
  Map<String, dynamic> holiday,
  DateTime referenceDate,
) {
  final storedDate = AppDateUtils.holidayRecordDate(
    holiday,
    fallbackYear: referenceDate.year,
  );
  final month =
      storedDate?.month ??
      AppDateUtils.parseMonth((holiday['month'] ?? '').toString());
  final day = storedDate?.day ?? _intValue(holiday['day']);
  if (month == null || day == null) return null;

  var occurrence = _validHolidayDate(referenceDate.year, month, day);
  if (occurrence == null) return null;
  if (occurrence.isBefore(referenceDate.subtract(const Duration(days: 1)))) {
    occurrence = _validHolidayDate(referenceDate.year + 1, month, day);
  }
  return occurrence;
}

DateTime? _holidayDateForDisplay(
  Map<String, dynamic> holiday,
  DateTime referenceDate,
) {
  final storedDate = AppDateUtils.holidayRecordDate(
    holiday,
    fallbackYear: referenceDate.year,
  );
  final month =
      storedDate?.month ??
      AppDateUtils.parseMonth((holiday['month'] ?? '').toString());
  final day = storedDate?.day ?? _intValue(holiday['day']);
  if (month == null || day == null) return null;

  final today = DateTime(
    referenceDate.year,
    referenceDate.month,
    referenceDate.day,
  );
  final recurring = holiday['isRecurring'] == true;
  final storedYear = storedDate?.year ?? _intValue(holiday['year']);

  if (!recurring && storedYear != null && storedYear > 0) {
    final exactDate = _validHolidayDate(storedYear, month, day);
    if (exactDate == null || exactDate.isBefore(today)) return null;
    return exactDate;
  }

  var occurrence = _validHolidayDate(today.year, month, day);
  if (occurrence == null) return null;
  if (occurrence.isBefore(today)) {
    occurrence = _validHolidayDate(today.year + 1, month, day);
  }
  return occurrence;
}
