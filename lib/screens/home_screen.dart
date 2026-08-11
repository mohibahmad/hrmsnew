import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/preferences_service.dart';
import 'workers.dart';
import 'attendance_screen.dart';
import 'workers_attendance_screen.dart';
import 'payroll_screen.dart';
import 'time_off.dart';
import 'assign_time_off.dart';
import 'assets_screen.dart';
import 'holidays_screen.dart';
import 'documents_screen.dart';
import 'expenses_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import '../utils/logout_dialog.dart';
import '../widgets/unsaved_changes_dialog.dart';
import '../widgets/notification_sidebar.dart';
import 'login_screen.dart';
import '../services/payroll_service.dart';
import '../services/dashboard_chart_service.dart';
import '../services/dummy_data.dart';
import '../services/error_reporter.dart';
import '../utils/date_utils.dart';
import '../utils/currency_utils.dart';
import '../widgets/custom_timeframe_dropdown.dart';
import '../widgets/sidebar_widget.dart';
import '../widgets/dashboard/top_header.dart';
import '../widgets/dashboard/total_workers_card.dart';
import '../widgets/dashboard/sparkline_card.dart';
import '../widgets/dashboard/attendance_line_chart.dart';
import '../widgets/dashboard/leave_types_pie_chart.dart';
import '../widgets/dashboard/holiday_card.dart';

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
  String _selectedPeriod = 'This Year';
  bool _showProfile = false;
  bool _showAssignTimeOff = false;
  bool _showNotifications = false;
  bool _showWorkersAttendance = false;
  final List<bool> _activatedScreens = List.filled(13, false);
  final GlobalKey<WorkersScreenState> _workersKey =
      GlobalKey<WorkersScreenState>();
  late AuthService _authService;
  late FirestoreService _firestore;
  String _currencyCode = CurrencyUtils.defaultCode;

  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return const SizedBox.shrink();
      case 1:
        return WorkersScreen(
          key: _workersKey,
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        );
      case 2:
        return AttendanceScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
          onWorkersAttendanceTap: () {
            setState(() {
              _showWorkersAttendance = true;
              _activatedScreens[11] = true;
            });
          },
        );
      case 3:
        return PayrollScreen(
          isActive:
              _getStackIndex() == 3 &&
              !_showAssignTimeOff &&
              !_showProfile &&
              !_showWorkersAttendance &&
              !_showNotifications,
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onAssignTimeOff: () {
            setState(() {
              _selectedTimeOffWorker = null;
              _showAssignTimeOff = true;
              _activatedScreens[9] = true;
            });
          },
          onNotificationTap: _toggleNotifications,
        );
      case 4:
        return TimeOffScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onAssignTimeOff: (worker) {
            setState(() {
              _selectedTimeOffWorker = worker;
              _showAssignTimeOff = true;
              _activatedScreens[9] = true;
            });
          },
          onNotificationTap: _toggleNotifications,
        );
      case 5:
        return AssetsScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        );
      case 6:
        return HolidaysScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        );
      case 7:
        return ExpensesScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        );
      case 8:
        return SettingsScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          isGuest: _authService.currentUser?.isAnonymous ?? false,
          onNotificationTap: _toggleNotifications,
        );
      case 9:
        return AssignTimeOffScreen(
          key: ValueKey(
            'assign_time_off_${_selectedTimeOffWorker?['id'] ?? _selectedTimeOffWorker?['workerId'] ?? _selectedTimeOffWorker?['email'] ?? 'new'}',
          ),
          onBack: () => setState(() {
            _showAssignTimeOff = false;
            _selectedTimeOffWorker = null;
          }),
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
          initialWorker: _selectedTimeOffWorker,
        );
      case 10:
        return DocumentsScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  int _getStackIndex() {
    if (_showWorkersAttendance) return 11;
    if (_showProfile) return 10;
    if (_showAssignTimeOff) return 9;
    if (_selectedIndex == 0) return 0;
    if (_selectedIndex == 1) return 1;
    if (_selectedIndex == 2) {
      if (_selectedSubIndex == 0) return 2;
      if (_selectedSubIndex == 1) return 3;
      if (_selectedSubIndex == 2) return 4;
      if (_selectedSubIndex == 3) return 5;
      if (_selectedSubIndex == 4) return 6;
      if (_selectedSubIndex == 5) return 12;
    }
    if (_selectedIndex == 3) return 7;
    if (_selectedIndex == 4) return 8;
    return 0;
  }

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
  StreamSubscription? _holidaysSub;
  StreamSubscription? _workersSub;
  StreamSubscription? _expensesSub;
  StreamSubscription? _payrollSub;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _timeoffSub;
  StreamSubscription? _notifSub;
  StreamSubscription<Map<String, dynamic>?>? _profileSub;
  int _unreadNotifCount = 0;
  List<Map<String, dynamic>> _allAttendanceDocs = [];
  List<Map<String, dynamic>> _allTimeoffDocs = [];

  Map<String, dynamic>? _selectedTimeOffWorker;

  bool _isPremium = PreferencesService.cachedIsPremium;
  bool _dashboardReady = false;
  bool _initialized = false;
  bool _workersLoaded = false;

  @override
  void dispose() {
    _holidaysSub?.cancel();
    _workersSub?.cancel();
    _expensesSub?.cancel();
    _payrollSub?.cancel();
    _attendanceSub?.cancel();
    _timeoffSub?.cancel();
    _notifSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  static num _parseAmount(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value;
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[^\d.]'), '');
      return double.tryParse(cleaned) ?? 0;
    }
    return 0;
  }

  static double _parseNumToDouble(dynamic value) =>
      _parseAmount(value).toDouble();

  Future<void> _loadPremiumStatus() async {
    bool isPremium = false;
    String currencyCode = _currencyCode;
    final user = _authService.currentUser;

    if (user != null && !user.isAnonymous) {
      try {
        final profile = await _firestore.getUserProfileOrThrow();
        isPremium = profile?['isPremium'] == true;
        currencyCode = CurrencyUtils.normalize(profile?['currency']);
        await PreferencesService.setPremium(isPremium);
      } catch (e, st) {
        ErrorReporter.report(e, st, context: 'loadPremiumStatus');

        isPremium = PreferencesService.cachedIsPremium;
      }
    }
    if (mounted) {
      setState(() {
        _isPremium = isPremium;
        _currencyCode = currencyCode;
      });
    }
  }

  Future<void> _checkProfileExistsOrLogout() async {
    final user = _authService.currentUser;
    if (user == null || user.isAnonymous) return;

    try {
      final profile = await _firestore.getUserProfileOrThrow();
      if (profile == null) {
        await _authService.signOut();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'checkProfileExistsOrLogout');
    }
  }

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

    final currentUser = _authService.currentUser;
    _restoreProfilePic(currentUser);
    _loadDashboardData();
    _startPremiumListener();

    if (currentUser?.isAnonymous ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handlePeriodChanged(_selectedPeriod);
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _dashboardReady = true);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkProfileExistsOrLogout();
      await _loadPremiumStatus();
    });
  }

  Future<void> _restoreProfilePic(User? currentUser) async {
    if (currentUser != null && !currentUser.isAnonymous) {
      try {
        final profile = await _firestore.getUserProfile();
        if (mounted) {
          final pic = profile?['profilePic'];
          if (pic != null && pic.toString().isNotEmpty) {
            AuthService.profilePicNotifier.value = pic.toString();
          } else {
            AuthService.profilePicNotifier.value = null;
          }
        }
      } catch (_) {
        AuthService.profilePicNotifier.value = null;
      }
      return;
    }

    final cachedUrl = PreferencesService.cachedProfilePicUrl;
    AuthService.profilePicNotifier.value =
        (cachedUrl != null && cachedUrl.isNotEmpty) ? cachedUrl : null;
  }

  void _startPremiumListener() {
    final user = _authService.currentUser;
    if (user == null || user.isAnonymous) return;
    _profileSub = _firestore.userProfileStream.listen(
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
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      setState(() {
        final workersList = DummyData.workers;
        _totalWorkersCount = workersList.length;
        int mCount = 0;
        int fCount = 0;
        int oCount = 0;
        for (final w in workersList) {
          final genderStr = (w['gender'] ?? '').toString().trim().toLowerCase();
          if (genderStr == 'female') {
            fCount++;
          } else if (genderStr == 'male') {
            mCount++;
          } else if (genderStr == 'other' || genderStr == 'others') {
            oCount++;
          }
        }
        _maleWorkersCount = mCount;
        _femaleWorkersCount = fCount;
        _otherWorkersCount = oCount;
        _allTimeoffDocs = List<Map<String, dynamic>>.from(DummyData.timeoff);
        _recalculateDummyTotals(_selectedPeriod);

        final rawHolidays = DummyData.holidays.values
            .expand((list) => list)
            .cast<Map<String, dynamic>>()
            .toList();
        _holidays = rawHolidays.map((h) {
          final dateStr = (h['date'] ?? '').toString();
          final parts = dateStr.split('/');
          final monthNames = [
            '',
            'January',
            'February',
            'March',
            'April',
            'May',
            'June',
            'July',
            'August',
            'September',
            'October',
            'November',
            'December',
          ];
          final weekDays = [
            'Sunday',
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
          ];
          String day = '';
          String month = '';
          String dayOfWeek = '';
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
              final dt = DateTime(year, monthNum, dayNum);
              dayOfWeek = weekDays[dt.weekday % 7];
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
        }).toList();

        final enrichedAttendance = List<Map<String, dynamic>>.from(
          DummyData.attendance,
        );
        for (final att in enrichedAttendance) {
          final status = (att['status'] ?? '').toString().trim().toLowerCase();
          if (status == 'leave') {
            final reason = (att['reason'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            if (reason == 'vacation') {
              att['type'] = 'Casual Leave';
            } else if (reason == 'medical') {
              att['type'] = 'Medical Leave';
            } else if (reason == 'sick') {
              att['type'] = 'Sick Leave';
            } else {
              att['type'] = 'Annual Leave';
            }
          }
        }
        _allAttendanceDocs = enrichedAttendance;

        _unreadNotifCount = DummyData.notifications
            .where((n) => n['isRead'] != true)
            .length;
        _workersDocs = List<Map<String, dynamic>>.from(DummyData.workers);
        _rawPayrollDocs = List<Map<String, dynamic>>.from(DummyData.payroll);
        _workersLoaded = true;
      });
    } else {
      setState(() {
        _holidays = [];
      });

      _holidaysSub = _firestore.holidaysStream.listen((snap) {
        if (mounted) {
          setState(() {
            _holidays = snap.docs
                .map((d) {
                  return {...d.data() as Map<String, dynamic>, 'id': d.id};
                })
                .where((holiday) => holiday['type'] != 'company_work_days')
                .toList();
          });
        }
      });

      _workersSub = _firestore.workersStream.listen((snap) {
        if (mounted) {
          int mCount = 0;
          int fCount = 0;
          int oCount = 0;
          final list = <Map<String, dynamic>>[];
          for (final doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            list.add({...data, 'id': doc.id});
            final genderStr = (data['gender'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            if (genderStr == 'female') {
              fCount++;
            } else if (genderStr == 'male') {
              mCount++;
            } else if (genderStr == 'other' || genderStr == 'others') {
              oCount++;
            }
          }
          setState(() {
            _totalWorkersCount = snap.docs.length;
            _maleWorkersCount = mCount;
            _femaleWorkersCount = fCount;
            _otherWorkersCount = oCount;
            _workersDocs = list;
            _workersLoaded = true;
            _recalculateSumsForPeriod(_selectedPeriod);
          });
        }
      });

      _attendanceSub = _firestore.attendanceStream.listen((snap) {
        if (mounted) {
          setState(() {
            _allAttendanceDocs = snap.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
          });
        }
      });

      _timeoffSub = _firestore.timeoffStream.listen((snap) {
        if (mounted) {
          setState(() {
            _allTimeoffDocs = snap.docs
                .map(
                  (doc) => {
                    ...doc.data() as Map<String, dynamic>,
                    'id': doc.id,
                  },
                )
                .toList();
          });
        }
      });

      _expensesSub = _firestore.expensesStream.listen((snap) {
        if (mounted) {
          setState(() {
            _rawExpensesDocs = snap.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>?;
              return {
                ...?data,
                'id': doc.id,
                'amount': _parseAmount(data?['amount']),
              };
            }).toList();
            _recalculateSumsForPeriod(_selectedPeriod);
          });
        }
      });

      _payrollSub = _firestore.payrollStream.listen((snap) {
        if (mounted) {
          setState(() {
            _rawPayrollDocs = snap.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>?;
              final savedNet = data?['netSalaryAmount'];
              final legacyFormattedNet = (data?['netSalary'] ?? '').toString();
              final netSalary = savedNet is num
                  ? savedNet.toDouble()
                  : legacyFormattedNet.trim().isNotEmpty
                  ? PayrollService.extractSalary(legacyFormattedNet)
                  : (PayrollService.calculatePayroll(
                              salary: (data?['salary'] ?? '').toString(),
                              totalWorkDays: (data?['totalWorkDays'] ?? '')
                                  .toString(),
                              absents: (data?['absents'] ?? '').toString(),
                              leaves: (data?['leaves'] ?? '').toString(),
                              overtimeAmount: (data?['overtimeAmount'] ?? '')
                                  .toString(),
                              absentDeductionPerDay:
                                  data?['deductionsAreTotals'] == true
                                  ? ''
                                  : (data?['absentDeduction'] ?? '').toString(),
                              leaveDeductionPerDay:
                                  data?['deductionsAreTotals'] == true
                                  ? ''
                                  : (data?['leaveDeduction'] ?? '').toString(),
                              salaryType: (data?['salaryType'] ?? 'Monthly')
                                  .toString(),
                            )['netSalary']
                            as num)
                        .toDouble();
              return {...?data, 'id': doc.id, 'netSalary': netSalary};
            }).toList();
            _recalculateSumsForPeriod(_selectedPeriod);
          });
        }
      });

      _notifSub = _firestore.notificationsStream.listen((snap) {
        if (mounted) {
          setState(() {
            _unreadNotifCount = snap.docs.where((d) {
              final data = d.data() as Map<String, dynamic>?;
              return data?['isRead'] != true;
            }).length;
          });
        }
      });
    }
  }

  void _handlePeriodChanged(String period) {
    setState(() {
      _selectedPeriod = period;
      final isGuest = _authService.currentUser?.isAnonymous ?? false;
      if (isGuest) {
        _recalculateDummyTotals(period);
      } else {
        _recalculateSumsForPeriod(period);
      }
    });
  }

  void _recalculateSumsForPeriod(String period) {
    final paidPayrollRecords =
        PayrollService.paidPayrollRecordsForActiveWorkers(
          _workersDocs,
          _rawPayrollDocs,
        );
    final paidPayrollKeys = paidPayrollRecords
        .map((record) => (record['payrollKey'] ?? '').toString().trim())
        .where((key) => key.isNotEmpty)
        .toSet();

    final payrollAmountByKey = <String, double>{};
    for (final record in paidPayrollRecords) {
      final key = (record['payrollKey'] ?? '').toString().trim();
      if (key.isEmpty) continue;
      final netSalary = _parseNumToDouble(record['netSalary']);
      if (netSalary > 0) {
        payrollAmountByKey[key] = netSalary;
      }
    }

    final activeExpenseRecords = _rawExpensesDocs.where((record) {
      final category = (record['category'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final payrollKey = (record['payrollKey'] ?? '').toString().trim();
      if (category != 'salary' || payrollKey.isEmpty) return true;
      return paidPayrollKeys.contains(payrollKey);
    }).toList();
    final expenseSeries = DashboardChartService.buildSeries(
      records: activeExpenseRecords,
      valueOf: (record) {
        final category = (record['category'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final payrollKey = (record['payrollKey'] ?? '').toString().trim();
        if (category == 'salary' && payrollKey.isNotEmpty) {
          return payrollAmountByKey[payrollKey] ?? 0.0;
        }
        return _parseNumToDouble(record['amount']);
      },
      period: period,
      dateOf: DashboardChartService.expenseRecordDate,
    );
    // The Total Salary card mirrors the salary expenses shown in the
    // Expenses screen: only expenses whose category is 'salary' count, and
    // payroll-linked ones are valued from the paid payroll (kept in sync when
    // the salary expense is edited). No salary expense means no salary data.
    final salaryExpenseRecords = activeExpenseRecords.where((record) {
      final category = (record['category'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return category == 'salary';
    }).toList();
    final salarySeries = DashboardChartService.buildSeries(
      records: salaryExpenseRecords,
      valueOf: (record) {
        final payrollKey = (record['payrollKey'] ?? '').toString().trim();
        if (payrollKey.isNotEmpty) {
          return payrollAmountByKey[payrollKey] ?? 0.0;
        }
        return _parseNumToDouble(record['amount']);
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
    final activePayrollRecords =
        PayrollService.paidPayrollRecordsForActiveWorkers(
          DummyData.workers,
          DummyData.payroll,
        );
    final payrollRecords = activePayrollRecords.map((item) {
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
    for (final record in payrollRecords) {
      final key = (record['payrollKey'] ?? '').toString().trim();
      if (key.isEmpty) continue;
      final netSalary = _parseNumToDouble(record['netSalary']);
      if (netSalary > 0) {
        payrollAmountByKey[key] = netSalary;
      }
    }

    final now = DateTime.now();
    int maxDays = 365;
    if (period == 'Today') {
      maxDays = 0;
    } else if (period == 'Week' || period == 'This Week') {
      maxDays = 7;
    } else if (period == 'Month' || period == 'This Month') {
      maxDays = 30;
    } else if (period == '6 Month' || period == 'Last 6 Months') {
      maxDays = 180;
    }

    final adjustedExpenses = DummyData.expenses.asMap().entries.map((entry) {
      final record = Map<String, dynamic>.from(entry.value);
      final int i = entry.key;
      int daysAgo = (i * (maxDays + 1) / DummyData.expenses.length).floor();
      final newDate = now.subtract(Duration(days: daysAgo));
      final dayStr = newDate.day.toString().padLeft(2, '0');
      final monthStr = newDate.month.toString().padLeft(2, '0');
      final yearStr = newDate.year.toString();
      record['date'] = '$dayStr/$monthStr/$yearStr';
      return record;
    }).toList();

    final filteredExpenses = adjustedExpenses.where((record) {
      final category = (record['category'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final payrollKey = (record['payrollKey'] ?? '').toString().trim();
      if (category == 'salary' && payrollKey.isNotEmpty) {
        return payrollAmountByKey.containsKey(payrollKey);
      }
      return true;
    }).toList();

    final expenseSeries = DashboardChartService.buildSeries(
      records: filteredExpenses,
      valueOf: (record) {
        final category = (record['category'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final payrollKey = (record['payrollKey'] ?? '').toString().trim();
        if (category == 'salary' && payrollKey.isNotEmpty) {
          return payrollAmountByKey[payrollKey] ?? 0.0;
        }
        return _parseNumToDouble(record['amount']);
      },
      period: period,
      dateOf: DashboardChartService.expenseRecordDate,
      placeUndatedInCurrentPeriod: true,
    );
    // Same rule as the real user path: the Total Salary card reflects the
    // salary expenses (payroll-linked values come from the paid payroll).
    final salaryExpenseRecords = filteredExpenses.where((record) {
      final category = (record['category'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return category == 'salary';
    }).toList();
    final salarySeries = DashboardChartService.buildSeries(
      records: salaryExpenseRecords,
      valueOf: (record) {
        final payrollKey = (record['payrollKey'] ?? '').toString().trim();
        if (payrollKey.isNotEmpty) {
          return payrollAmountByKey[payrollKey] ?? 0.0;
        }
        return _parseNumToDouble(record['amount']);
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
        .map(
          (worker) =>
              (worker['id'] ?? worker['workerId'] ?? '').toString().trim(),
        )
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  bool _attendanceBelongsToExistingWorker(Map<String, dynamic> attendance) {
    if (_authService.currentUser?.isAnonymous ?? false) return true;
    if (!_workersLoaded) return true;
    if (_workersDocs.isEmpty) return false;

    final workerId = (attendance['workerId'] ?? '').toString().trim();
    if (workerId.isNotEmpty) return _existingWorkerIds.contains(workerId);

    final email = (attendance['email'] ?? '').toString().trim().toLowerCase();
    if (email.isNotEmpty) {
      return _workersDocs.any(
        (worker) =>
            (worker['email'] ?? '').toString().trim().toLowerCase() == email,
      );
    }

    final name = (attendance['name'] ?? attendance['workerName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (name.isEmpty) return false;
    return _workersDocs.any(
      (worker) =>
          (worker['name'] ?? '').toString().trim().toLowerCase() == name,
    );
  }

  /// Present and absent attendance records for the selected timeframe that
  /// belong to current workers. Dashboard filtering uses only the canonical
  /// `attendanceDate`; `createdAt` and document IDs are metadata.
  List<Map<String, dynamic>> _getFilteredAttendanceDocs() {
    final isGuest =
        (_authService.currentUser?.isAnonymous ?? false) ||
        PreferencesService.cachedIsGuest;

    final rawDocs = isGuest ? DummyData.attendance : _allAttendanceDocs;

    final workersList = isGuest ? DummyData.workers : _workersDocs;
    final validWorkerIds = <String>{};
    final validEmails = <String>{};
    for (final w in workersList) {
      final id = (w['id'] ?? w['workerId'] ?? '').toString().trim();
      if (id.isNotEmpty) validWorkerIds.add(id);
      final email = (w['email'] ?? '').toString().trim().toLowerCase();
      if (email.isNotEmpty) validEmails.add(email);
    }

    return rawDocs.where((attendance) {
      final s = (attendance['status'] ?? '').toString().trim().toLowerCase();
      if (s != 'present' && s != 'absent') return false;
      if (!AppDateUtils.isAttendanceRecordWithinPeriod(
        attendance,
        _selectedPeriod,
      )) {
        return false;
      }

      if (workersList.isNotEmpty) {
        final rId = (attendance['workerId'] ?? attendance['id'] ?? '')
            .toString()
            .trim();
        final rEmail = (attendance['email'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final belongsToWorker =
            (rId.isNotEmpty && validWorkerIds.contains(rId)) ||
            (rEmail.isNotEmpty && validEmails.contains(rEmail));
        if (!belongsToWorker) return false;
      }

      return true;
    }).toList();
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

  bool _holidayFallsWithinSelectedPeriod(int daysUntilHoliday) {
    switch (_selectedPeriod) {
      case 'Today':
        return daysUntilHoliday == 0;
      case 'Week':
      case 'This Week':
        return daysUntilHoliday <= 7;
      case 'Month':
      case 'This Month':
        return daysUntilHoliday <= 30;
      case '6 Month':
      case 'Last 6 Months':
        return daysUntilHoliday <= 180;
      case 'This Year':
        return daysUntilHoliday <= 365;
      default:
        return true;
    }
  }

  void _handleLogout() {
    showLogoutDialog(context);
  }

  bool _backToLoginInProgress = false;
  bool _isGuest = false;

  Future<void> _handleBackToLogin() async {
    if (_backToLoginInProgress) return;
    _backToLoginInProgress = true;
    setState(() {
      _isGuest = true;
    });
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

  void _openProfile() {
    setState(() {
      _showProfile = true;
      _showWorkersAttendance = false;
      _showAssignTimeOff = false;
      _showNotifications = false;
      _selectedTimeOffWorker = null;
      _activatedScreens[10] = true;
    });
  }

  void _toggleNotifications() {
    final opening = !_showNotifications;
    setState(() {
      _showNotifications = opening;
    });
    if (opening) {
      _markNotificationsSeen();
    }
  }

  Future<void> _markNotificationsSeen() async {
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) return;
    try {
      await _firestore.markAllNotificationsRead();
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'MarkNotificationsSeen');
    }
  }

  void _handleNotificationNavigation(String type) {
    setState(() {
      _showNotifications = false;
      switch (type) {
        case 'worker_added':
          _selectedIndex = 1;
          break;
        case 'attendance_marked':
          _selectedIndex = 2;
          _selectedSubIndex = 0;
          break;
        case 'payroll_added':
        case 'payroll_due':
          _selectedIndex = 2;
          _selectedSubIndex = 1;
          break;
        case 'time_off_added':
          _selectedIndex = 2;
          _selectedSubIndex = 2;
          break;
        case 'asset_added':
          _selectedIndex = 2;
          _selectedSubIndex = 3;
          break;
        case 'holiday_added':
          _selectedIndex = 2;
          _selectedSubIndex = 4;
          break;
        case 'expense_added':
          _selectedIndex = 3;
          break;
        default:
          break;
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
          final double bodyWidth = constraints.maxWidth < minWidth
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
                    isGuest:
                        _isGuest ||
                        (_authService.currentUser?.isAnonymous ?? false),
                    isPremium: _isPremium,
                    onItemSelected: (index, {subIndex}) async {
                      if (_selectedIndex == 1 &&
                          _workersKey.currentState?.hasUnsavedChanges == true) {
                        final shouldDiscard = await _workersKey.currentState!
                            .confirmDiscardChanges();
                        if (!shouldDiscard) return;
                      }
                      if (_showAssignTimeOff) {
                        final shouldDiscard = await UnsavedChangesDialog.show(
                          context,
                        );
                        if (!shouldDiscard) return;
                      }
                      setState(() {
                        _selectedIndex = index;
                        if (subIndex != null) {
                          _selectedSubIndex = subIndex;
                        }
                        _showProfile = false;
                        _showWorkersAttendance = false;
                        _showAssignTimeOff = false;
                        _showNotifications = false;
                        _selectedTimeOffWorker = null;
                        _activatedScreens[_getStackIndex()] = true;
                      });
                    },
                    onBackToLogin: _handleBackToLogin,
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Builder(
                          builder: (context) {
                            final int stackIndex = _getStackIndex();
                            return IndexedStack(
                              index: stackIndex,
                              children: [
                                _activatedScreens[0]
                                    ? (_dashboardReady
                                          ? TweenAnimationBuilder<double>(
                                              key: ValueKey(stackIndex == 0),
                                              tween: Tween<double>(
                                                begin: 0,
                                                end: 1,
                                              ),
                                              duration: const Duration(
                                                milliseconds: 650,
                                              ),
                                              curve: Curves.easeOutQuart,
                                              builder: (context, value, child) {
                                                return Opacity(
                                                  opacity: value,
                                                  child: Transform.translate(
                                                    offset: Offset(
                                                      0,
                                                      15 * (1 - value),
                                                    ),
                                                    child: child,
                                                  ),
                                                );
                                              },
                                              child: _buildDashboardView(),
                                            )
                                          : Column(
                                              children: [
                                                TopHeader(
                                                  onProfileTap: _openProfile,
                                                  onNotificationTap:
                                                      _toggleNotifications,
                                                  unreadCount:
                                                      _unreadNotifCount,
                                                ),
                                                const Expanded(
                                                  child: Center(
                                                    child:
                                                        CircularProgressIndicator(),
                                                  ),
                                                ),
                                              ],
                                            ))
                                    : const SizedBox.shrink(),

                                _activatedScreens[1]
                                    ? _getScreen(1)
                                    : const SizedBox.shrink(),

                                _activatedScreens[2]
                                    ? _getScreen(2)
                                    : const SizedBox.shrink(),

                                _activatedScreens[3]
                                    ? _getScreen(3)
                                    : const SizedBox.shrink(),

                                _activatedScreens[4]
                                    ? _getScreen(4)
                                    : const SizedBox.shrink(),

                                _activatedScreens[5]
                                    ? _getScreen(5)
                                    : const SizedBox.shrink(),

                                _activatedScreens[6]
                                    ? _getScreen(6)
                                    : const SizedBox.shrink(),

                                _activatedScreens[7]
                                    ? _getScreen(7)
                                    : const SizedBox.shrink(),

                                _activatedScreens[8]
                                    ? _getScreen(8)
                                    : const SizedBox.shrink(),

                                _activatedScreens[9]
                                    ? _getScreen(9)
                                    : const SizedBox.shrink(),

                                _activatedScreens[10]
                                    ? _buildProfileView(stackIndex == 10)
                                    : const SizedBox.shrink(),

                                _activatedScreens[11]
                                    ? WorkersAttendanceScreen(
                                        hideSidebar: true,
                                        onProfileTap: _openProfile,
                                        onBack: () {
                                          setState(() {
                                            _showWorkersAttendance = false;
                                          });
                                        },
                                        onNotificationTap: _toggleNotifications,
                                      )
                                    : const SizedBox.shrink(),

                                _activatedScreens[12]
                                    ? _getScreen(10)
                                    : const SizedBox.shrink(),
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

  Widget _buildDashboardView() {
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    final unreadCount = isGuest
        ? DummyData.notifications.where((n) => n['isRead'] != true).length
        : _unreadNotifCount;
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
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF000000),
                        fontFamily: 'SF Pro Display',
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
                      child: Text(
                        'attendance_overview'.tr(),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'leave_types'.tr(),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Builder(
                  builder: (context) {
                    final isGuest =
                        (_authService.currentUser?.isAnonymous ?? false) ||
                        PreferencesService.cachedIsGuest;
                    final leaveDocs =
                        DashboardChartService.mergedLeaveDaysForPeriod(
                          timeOffRecords: _allTimeoffDocs,
                          attendanceRecords: isGuest
                              ? const <Map<String, dynamic>>[]
                              : _allAttendanceDocs
                                    .where(_attendanceBelongsToExistingWorker)
                                    .toList(),
                          period: _selectedPeriod,
                          workers: _workersDocs,
                        );
                    final filteredAttendanceDocs = _getFilteredAttendanceDocs();
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: AttendanceLineChart(
                              period: _selectedPeriod,
                              isEmpty:
                                  filteredAttendanceDocs.isEmpty ||
                                  _totalWorkersCount == 0,
                              attendanceDocs: filteredAttendanceDocs,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
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

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'upcoming_holidays'.tr(),
                      style: TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Builder(
                  builder: (context) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFFFFFFFF).withValues(alpha: 0.45),
                            blurRadius: 12,
                            spreadRadius: 1.5,
                          ),
                        ],
                      ),
                      child: () {
                        final current = DateTime.now();
                        final today = DateTime(
                          current.year,
                          current.month,
                          current.day,
                        );
                        final isGuest =
                            _authService.currentUser?.isAnonymous ?? false;
                        final activeHolidays = <Map<String, dynamic>>[];
                        for (final source in _holidays) {
                          if (source['isEnabled'] == false) continue;
                          final holidayDate = isGuest
                              ? _guestHolidayDateForDisplay(source, current)
                              : _holidayDateForDisplay(source, today);
                          if (holidayDate == null) continue;
                          final daysUntilHoliday = holidayDate
                              .difference(isGuest ? current : today)
                              .inDays;
                          if (daysUntilHoliday < 0 ||
                              !_holidayFallsWithinSelectedPeriod(
                                daysUntilHoliday,
                              )) {
                            continue;
                          }
                          final holiday = Map<String, dynamic>.from(source);
                          holiday['day'] = holidayDate.day;
                          holiday['month'] = DateFormat(
                            'MMMM',
                            'en_US',
                          ).format(holidayDate);
                          holiday['remainingDays'] = daysUntilHoliday
                              .toString();
                          holiday['dayOfWeek'] = DateFormat(
                            'EEEE',
                            context.locale.toString(),
                          ).format(holidayDate);
                          activeHolidays.add(holiday);
                        }
                        activeHolidays.sort((a, b) {
                          final aDays =
                              int.tryParse(
                                a['remainingDays']?.toString() ?? '',
                              ) ??
                              9999;
                          final bDays =
                              int.tryParse(
                                b['remainingDays']?.toString() ?? '',
                              ) ??
                              9999;
                          return aDays.compareTo(bDays);
                        });

                        final groupedHolidays = <Map<String, dynamic>>[];
                        for (final h in activeHolidays) {
                          final key = '${h['day']}_${h['month']}';
                          final existing = groupedHolidays
                              .cast<Map<String, dynamic>?>()
                              .firstWhere(
                                (g) => '${g!['day']}_${g['month']}' == key,
                                orElse: () => null,
                              );
                          if (existing != null) {
                            final existingNames =
                                (existing['holidayNamesList'] ?? <String>[])
                                    as List;
                            final newName = (h['name'] ?? '').toString();
                            if (!existingNames.contains(newName)) {
                              existingNames.add(newName);
                              existing['holidayNamesList'] = existingNames;
                            }
                          } else {
                            final grouped = Map<String, dynamic>.from(h);
                            final newName = (h['name'] ?? '').toString();
                            grouped['holidayNamesList'] = <String>[newName];
                            groupedHolidays.add(grouped);
                          }
                        }

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
                                      fontFamily: 'SF Pro Display',
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
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                            const SizedBox(height: 24),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                double spacing = 16.0;
                                double itemWidth =
                                    (constraints.maxWidth - (spacing * 4)) / 5;

                                return Wrap(
                                  spacing: spacing,
                                  runSpacing: spacing,
                                  children: groupedHolidays.map((h) {
                                    final remainingDaysStr =
                                        (h['remainingDays'] ?? '').toString();
                                    final remainingDaysInt =
                                        int.tryParse(remainingDaysStr) ?? -1;
                                    final isUrgent =
                                        remainingDaysInt >= 0 &&
                                        remainingDaysInt <= 5;

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
                                            (h['holidayNamesList']
                                                as List<String>?) ??
                                            <String>[
                                              (h['name'] ?? '').toString(),
                                            ],
                                        isActive: isUrgent,
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        );
                      }(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
