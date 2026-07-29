import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
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
import '../widgets/notification_sidebar.dart';
import 'login_screen.dart';
import '../services/payroll_service.dart';
import '../services/dashboard_chart_service.dart';
import '../services/dummy_data.dart';
import '../utils/date_utils.dart';
import '../widgets/custom_timeframe_dropdown.dart';
import '../widgets/sidebar_widget.dart';
import '../widgets/dashboard/top_header.dart';
import '../widgets/dashboard/total_workers_card.dart';
import '../widgets/dashboard/sparkline_card.dart';
import '../widgets/dashboard/attendance_line_chart.dart';
import '../widgets/dashboard/leave_types_pie_chart.dart';
import '../widgets/dashboard/holiday_card.dart';

class HomeScreen extends StatefulWidget {
  final int initialIndex;
  final int initialSubIndex;

  const HomeScreen({
    super.key,
    this.initialIndex = 0,
    this.initialSubIndex = 0,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _selectedIndex;
  late int _selectedSubIndex;
  String _selectedPeriod = 'Yearly';
  bool _showProfile = false;
  bool _showAssignTimeOff = false;
  bool _showNotifications = false;
  bool _showWorkersAttendance = false;
  final List<bool> _activatedScreens = List.filled(13, false);
  final GlobalKey<WorkersScreenState> _workersKey = GlobalKey<WorkersScreenState>();
  late AuthService _authService;
  late FirestoreService _firestore;

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
            });
          },
        );
      case 3:
        return PayrollScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onAssignTimeOff: () {
            setState(() {
              _selectedTimeOffWorker = null;
              _showAssignTimeOff = true;
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
  int _totalAttendanceCount = 0;
  int _totalTimeoffCount = 0;
  int _unreadNotifCount = 0;
  List<Map<String, dynamic>> _allAttendanceDocs = [];
  List<Map<String, dynamic>> _attendanceDocs = [];

  Map<String, dynamic>? _selectedTimeOffWorker;
  bool _isPremium = false;
  bool _dashboardReady = false;
  bool _initialized = false;

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
    final user = _authService.currentUser;

    if (user != null && !user.isAnonymous) {
      try {
        final profile = await _firestore.getUserProfile();
        isPremium = profile?['isPremium'] == true;

        await PreferencesService.setPremium(isPremium);
      } catch (_) {
        isPremium = await PreferencesService.isPremium();
      }
    }
    if (mounted) setState(() => _isPremium = isPremium);
  }

  Future<void> _checkProfileExistsOrLogout() async {
    final user = _authService.currentUser;
    if (user == null || user.isAnonymous) return;

    try {
      final profile = await _firestore.getUserProfile();
      if (profile == null) {
        await _authService.signOut();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      }
    } catch (_) {}
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

    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);

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
        if (mounted && profile != null) {
          final pic = profile['profilePic'];
          if (pic != null && pic.toString().isNotEmpty) {
            AuthService.profilePicNotifier.value = pic.toString();
            await PreferencesService.setProfilePicUrl(pic.toString());
            return;
          }
        }
      } catch (_) {}
    }

    final cachedUrl = PreferencesService.cachedProfilePicUrl;
    if (cachedUrl != null &&
        cachedUrl.isNotEmpty &&
        cachedUrl.startsWith('http')) {
      AuthService.profilePicNotifier.value = cachedUrl;
    } else {
      AuthService.profilePicNotifier.value = null;
    }
  }

  void _startPremiumListener() {
    final user = _authService.currentUser;
    if (user == null || user.isAnonymous) return;
    _profileSub = _firestore.userProfileStream.listen((profile) async {
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
      await PreferencesService.setPremium(isPremium);
      if (mounted && _isPremium != isPremium) {
        setState(() => _isPremium = isPremium);
      }
    });
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
        _totalTimeoffCount = DummyData.timeoff.length;
        _recalculateDummyTotals(_selectedPeriod);
        
        
        final rawHolidays = DummyData.holidays.values
            .expand((list) => list)
            .cast<Map<String, dynamic>>()
            .toList();
        _holidays = rawHolidays.map((h) {
          final dateStr = (h['date'] ?? '').toString();
          final parts = dateStr.split('/');
          final monthNames = [
            '', 'January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December',
          ];
          final weekDays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
          String day = '';
          String month = '';
          String dayOfWeek = '';
          if (parts.length == 3) {
            final dayNum = int.tryParse(parts[0]) ?? 0;
            final monthNum = int.tryParse(parts[1]) ?? 0;
            final year = int.tryParse(parts[2]) ?? DateTime.now().year;
            day = dayNum.toString();
            month = monthNum >= 1 && monthNum <= 12 ? monthNames[monthNum] : '';
            if (monthNum >= 1 && monthNum <= 12 && dayNum >= 1 && dayNum <= 31) {
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
            final reason = (att['reason'] ?? '').toString().trim().toLowerCase();
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
        _attendanceDocs = enrichedAttendance;
        _totalAttendanceCount = _attendanceDocs.length;

        _unreadNotifCount = DummyData.notifications
            .where((n) => n['isRead'] != true)
            .length;
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
          });
        }
      });

      _attendanceSub = _firestore.attendanceStream.listen((snap) {
        if (mounted) {
          setState(() {
            final today = DateTime.now();
            _allAttendanceDocs = snap.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            _attendanceDocs = _allAttendanceDocs.where((att) {
              final createdAt = att['createdAt'];
              if (createdAt == null) return false;
              DateTime? dt;
              if (createdAt is DateTime) {
                dt = createdAt;
              } else if (createdAt is String) {
                dt = DateTime.tryParse(createdAt);
              } else if (createdAt is Timestamp) {
                dt = createdAt.toDate();
              }
              return dt != null &&
                  dt.year == today.year &&
                  dt.month == today.month &&
                  dt.day == today.day;
            }).toList();
            _totalAttendanceCount = _attendanceDocs.length;
          });
        }
      });

      _timeoffSub = _firestore.timeoffStream.listen((snap) {
        if (mounted) {
          setState(() {
            _totalTimeoffCount = snap.docs.length;
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
              final result = PayrollService.calculatePayroll(
                salary: (data?['salary'] ?? '').toString(),
                totalWorkDays: (data?['totalWorkDays'] ?? '').toString(),
                absents: (data?['absents'] ?? '').toString(),
                leaves: (data?['leaves'] ?? '').toString(),
                overtimeAmount: (data?['overtimeAmount'] ?? '').toString(),
                salaryType: (data?['salaryType'] ?? 'Monthly').toString(),
              );
              return {
                ...?data,
                'id': doc.id,
                'netSalary': result['netSalary'] as double,
              };
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
    final expenseSeries = DashboardChartService.buildSeries(
      records: _rawExpensesDocs,
      valueOf: (record) => _parseNumToDouble(record['amount']),
      period: period,
      dateOf: DashboardChartService.expenseRecordDate,
    );
    final salarySeries = DashboardChartService.buildSeries(
      records: _rawPayrollDocs,
      valueOf: (record) => _parseNumToDouble(record['netSalary']),
      period: period,
    );

    _expenseChartPoints = expenseSeries.points;
    _salaryChartPoints = salarySeries.points;
    _totalExpensesSum = expenseSeries.total;
    _totalSalarySum = salarySeries.total;
  }

  void _recalculateDummyTotals(String period) {
    final expenseSeries = DashboardChartService.buildSeries(
      records: DummyData.expenses,
      valueOf: (record) => _parseNumToDouble(record['amount']),
      period: period,
      dateOf: DashboardChartService.expenseRecordDate,
      placeUndatedInCurrentPeriod: true,
    );
    final payrollRecords = DummyData.payroll.map((item) {
      final result = PayrollService.calculatePayroll(
        salary: (item['salary'] ?? '').toString(),
        totalWorkDays: (item['totalWorkDays'] ?? '').toString(),
        absents: (item['absents'] ?? '').toString(),
        leaves: (item['leaves'] ?? '').toString(),
        overtimeAmount: (item['overtimeAmount'] ?? '').toString(),
        salaryType: (item['salaryType'] ?? 'Monthly').toString(),
      );
      return {...item, 'netSalary': result['netSalary'] as double};
    }).toList();
    final totalDummySalary = payrollRecords.fold<double>(
      0,
      (sum, record) => sum + _parseNumToDouble(record['netSalary']),
    );
    final salarySeries = DashboardChartService.buildGuestSalarySeries(
      salaryRecords: payrollRecords,
      expenses: DummyData.expenses,
      totalSalary: totalDummySalary,
      period: period,
    );

    _expenseChartPoints = expenseSeries.points;
    _salaryChartPoints = salarySeries.points;
    _totalExpensesSum = expenseSeries.total;
    _totalSalarySum = salarySeries.total;
  }

  List<Map<String, dynamic>> _getFilteredAttendanceDocs(String period) {
    final now = DateTime.now();
    return _allAttendanceDocs.where((att) {
      final createdAt = att['createdAt'];
      DateTime? dt;
      if (createdAt != null) {
        if (createdAt is DateTime) {
          dt = createdAt;
        } else if (createdAt is String) {
          dt = DateTime.tryParse(createdAt);
        } else if (createdAt is Timestamp) {
          dt = createdAt.toDate();
        }
      } else {
        
        
        final id = att['id']?.toString() ?? '';
        final numericPart = id.replaceAll(RegExp(r'[^0-9]'), '');
        final num = numericPart.isNotEmpty ? int.tryParse(numericPart) ?? 0 : 0;
        dt = now.subtract(Duration(days: num % 90));
      }

      if (dt == null) return true;
      final diff = now.difference(dt);
      switch (period) {
        case 'Today':
          return diff.inDays == 0;
        case 'Week':
          return diff.inDays <= 7;
        case 'Month':
          return diff.inDays <= 30;
        case '6 Month':
          return diff.inDays <= 180;
        case 'Yearly':
        default:
          return true;
      }
    }).toList();
  }

  void _handleLogout() {
    showLogoutDialog(context);
  }

  void _handleBackToLogin() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _openProfile() {
    setState(() {
      _showProfile = true;
      _showWorkersAttendance = false;
      _showAssignTimeOff = false;
      _showNotifications = false;
      _selectedTimeOffWorker = null;
    });
  }

  void _toggleNotifications() {
    final willShow = !_showNotifications;
    setState(() {
      _showNotifications = willShow;
    });
    if (willShow) {
      _firestore.markAllNotificationsRead();
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
                    isGuest: _authService.currentUser?.isAnonymous ?? false,
                    isPremium: _isPremium,
                    onItemSelected: (index, {subIndex}) async {
                      
                      if (_selectedIndex == 1 && _workersKey.currentState?.hasUnsavedBulkChanges == true) {
                        final shouldDiscard = await _workersKey.currentState!.confirmDiscardBulkChanges();
                        if (!shouldDiscard) return;
                      }
                      setState(() {
                        _selectedIndex = index;
                        _activatedScreens[index] = true;
                        if (subIndex != null) {
                          _selectedSubIndex = subIndex;
                        }
                        _showProfile = false;
                        _showWorkersAttendance = false;
                        _showAssignTimeOff = false;
                        _showNotifications = false;
                        _selectedTimeOffWorker = null;
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

                                _getScreen(1),

                                _getScreen(2),

                                _getScreen(3),

                                _getScreen(4),

                                _getScreen(5),

                                _getScreen(6),

                                _getScreen(7),

                                _getScreen(8),

                                _getScreen(9),

                                _buildProfileView(stackIndex == 10),

                                WorkersAttendanceScreen(
                                  hideSidebar: true,
                                  onProfileTap: _openProfile,
                                  onBack: () {
                                    setState(() {
                                      _showWorkersAttendance = false;
                                    });
                                  },
                                  onNotificationTap: _toggleNotifications,
                                ),

                                _getScreen(10),
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
    return Column(
      children: [
        TopHeader(
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
          unreadCount: _unreadNotifCount,
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
                Text(
                  'dashboard'.tr(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF000000),
                    fontFamily: 'SF Pro Display',
                  ),
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
                          title: 'total_salary'.tr(),
                          amount:
                              '\$${NumberFormat.compact(locale: 'en_US').format(_totalSalarySum.clamp(0, double.infinity))}',
                          rawValue: _totalSalarySum,
                          points: _salaryChartPoints,
                          period: _selectedPeriod,
                          lineColor: const Color(0xFF4C84E0),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SparklineCard(
                          title: 'expenses'.tr(),
                          amount:
                              '\$${NumberFormat.compact(locale: 'en_US').format(_totalExpensesSum)}',
                          rawValue: _totalExpensesSum,
                          points: _expenseChartPoints,
                          period: _selectedPeriod,
                          lineColor: const Color(0xFF0EA5E9),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'attendance_overview'.tr(),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
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
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          CustomTimeframeDropdown(
                            selectedPeriod: _selectedPeriod,
                            onChanged: _handlePeriodChanged,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Builder(
                  builder: (context) {
                    final double screenWidth = MediaQuery.of(
                      context,
                    ).size.width;
                    final bool isNarrow = screenWidth < 1150;
                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Transform.translate(
                            offset: const Offset(-10, 0),
                            child: AttendanceLineChart(
                              period: _selectedPeriod,
                              isEmpty:
                                  _totalAttendanceCount == 0 ||
                                  _totalWorkersCount == 0,
                              attendanceDocs: _getFilteredAttendanceDocs(
                                _selectedPeriod,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          LeaveTypesPieChart(
                            period: _selectedPeriod,
                            isEmpty:
                                _totalTimeoffCount == 0 ||
                                _totalWorkersCount == 0,
                            attendanceDocs: _getFilteredAttendanceDocs(
                              _selectedPeriod,
                            ),
                          ),
                        ],
                      );
                    } else {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Transform.translate(
                                offset: const Offset(-10, 0),
                                child: AttendanceLineChart(
                                  period: _selectedPeriod,
                                  isEmpty:
                                      _totalAttendanceCount == 0 ||
                                      _totalWorkersCount == 0,
                                  attendanceDocs: _getFilteredAttendanceDocs(
                                    _selectedPeriod,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: LeaveTypesPieChart(
                                period: _selectedPeriod,
                                isEmpty:
                                    _totalTimeoffCount == 0 ||
                                    _totalWorkersCount == 0,
                                attendanceDocs: _getFilteredAttendanceDocs(
                                  _selectedPeriod,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'upcoming_holidays'.tr(),
                      style: TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
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
                        final now = DateTime.now();
                        final activeHolidays = _holidays.where((h) {
                          if (h['isEnabled'] != true) return false;

                          final monthStr = (h['month'] ?? '').toString();
                          final dayStr = (h['day'] ?? '').toString();
                          if (monthStr.isEmpty || dayStr.isEmpty) return false;

                          final monthNum = AppDateUtils.parseMonth(monthStr);
                          if (monthNum == null) return false;
                          final dayNum = int.tryParse(dayStr);
                          if (dayNum == null) return false;

                          var holidayDate = DateTime(
                            now.year,
                            monthNum,
                            dayNum,
                          );
                          if (holidayDate.isBefore(
                            now.subtract(const Duration(days: 1)),
                          )) {
                            holidayDate = DateTime(
                              now.year + 1,
                              monthNum,
                              dayNum,
                            );
                          }

                          final daysUntilHoliday = holidayDate
                              .difference(now)
                              .inDays;
                          if (daysUntilHoliday < 0) return false;

                          switch (_selectedPeriod) {
                            case 'Today':
                              return daysUntilHoliday == 0;
                            case 'Week':
                              return daysUntilHoliday <= 7;
                            case 'Month':
                              return daysUntilHoliday <= 30;
                            case '6 Month':
                              return daysUntilHoliday <= 180;
                            case 'Yearly':
                              return daysUntilHoliday <= 365;
                            default:
                              return true;
                          }
                        }).toList();

                        for (final h in activeHolidays) {
                          final daysUntil = _daysUntilHoliday(h, now);
                          h['remainingDays'] = daysUntil != null
                              ? daysUntil.toString()
                              : (h['remainingDays']?.toString() ?? '0');
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
                        if (activeHolidays.isEmpty) {
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
                                  children: activeHolidays.map((h) {
                                    final remainingDaysStr =
                                        h['remainingDays'] ?? '';
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
                                        holidayName: h['name'] ?? '',
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
            padding: EdgeInsets.symmetric(horizontal: 40.0, vertical: 30.0),
            child: ProfileBody(isActive: isActive),
          ),
        ),
      ],
    );
  }
}

int? _daysUntilHoliday(Map<String, dynamic> h, DateTime now) {
  final monthStr = (h['month'] ?? '').toString();
  final dayStr = (h['day'] ?? '').toString();
  if (monthStr.isEmpty || dayStr.isEmpty) return null;
  final monthNum = AppDateUtils.parseMonth(monthStr);
  final dayNum = int.tryParse(dayStr);
  if (monthNum == null || dayNum == null) return null;
  var holidayDate = DateTime(now.year, monthNum, dayNum);
  if (holidayDate.isBefore(now.subtract(const Duration(days: 1)))) {
    holidayDate = DateTime(now.year + 1, monthNum, dayNum);
  }
  final daysUntil = holidayDate.difference(now).inDays;
  return daysUntil >= 0 ? daysUntil : null;
}
