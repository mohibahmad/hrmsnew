import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/preferences_service.dart';

import 'workers.dart';
import 'pricing_screen.dart';
import 'attendance_screen.dart';
import 'payroll_screen.dart';
import 'time_off.dart';
import 'assign_time_off.dart';
import 'assets_screen.dart';
import 'holidays_screen.dart';
import 'expenses_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import '../utils/logout_dialog.dart';
import 'login_screen.dart';
import '../services/payroll_service.dart';
import '../services/dummy_data.dart';
import '../utils/date_utils.dart';
import '../widgets/custom_timeframe_dropdown.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int _selectedSubIndex = 0;
  String _selectedPeriod = 'Yearly';
  final ValueNotifier<String> _selectedHolidaysPeriod = ValueNotifier('Yearly');
  bool _showProfile = false;
  bool _showAssignTimeOff = false;
  final List<bool> _activatedScreens = List.filled(11, false);

  Widget _getScreen(int index) {
    if (!_activatedScreens[index]) {
      return const SizedBox.shrink();
    }
    switch (index) {
      case 1:
        return WorkersScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _navigateToAttendance,
        );
      case 2:
        return AttendanceScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _navigateToAttendance,
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
          onNotificationTap: _navigateToAttendance,
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
          onNotificationTap: _navigateToAttendance,
        );
      case 5:
        return AssetsScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _navigateToAttendance,
        );
      case 6:
        return HolidaysScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _navigateToAttendance,
        );
      case 7:
        return ExpensesScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _navigateToAttendance,
        );
      case 8:
        return SettingsScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          isGuest: AuthService().currentUser?.isAnonymous ?? false,
          onNotificationTap: _navigateToAttendance,
        );
      case 9:
        return AssignTimeOffScreen(
          onBack: () => setState(() {
            _showAssignTimeOff = false;
            _selectedTimeOffWorker = null;
          }),
          onNotificationTap: _navigateToAttendance,
          initialWorker: _selectedTimeOffWorker,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  int _getStackIndex() {
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
    }
    if (_selectedIndex == 3) return 7;
    if (_selectedIndex == 4) return 8;
    return 0;
  }

  int _totalWorkersCount = 0;
  int _maleWorkersCount = 0;
  int _femaleWorkersCount = 0;
  double _totalExpensesSum = 0.0;
  double _totalSalarySum = 0.0;
  List<Map<String, dynamic>> _holidays = [];
  StreamSubscription? _holidaysSub;
  StreamSubscription? _workersSub;
  StreamSubscription? _expensesSub;
  StreamSubscription? _payrollSub;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _timeoffSub;
  StreamSubscription<Map<String, dynamic>?>? _profileSub;
  int _totalAttendanceCount = 0;
  int _totalTimeoffCount = 0;
  List<Map<String, dynamic>> _attendanceDocs = [];
  List<Map<String, dynamic>> _timeoffDocs = [];
  List<Map<String, dynamic>> _workersList = [];
  Map<String, dynamic>? _selectedTimeOffWorker;
  bool _isPremium = false;

  @override
  void dispose() {
    _holidaysSub?.cancel();
    _workersSub?.cancel();
    _expensesSub?.cancel();
    _payrollSub?.cancel();
    _attendanceSub?.cancel();
    _timeoffSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPremiumStatus() async {
    bool isPremium = false;
    final user = AuthService().currentUser;
    // Always read premium status from Firestore, never trust local cache.
    if (user != null && !user.isAnonymous) {
      try {
        final profile = await FirestoreService().getUserProfile();
        isPremium = profile?['isPremium'] == true;
        // Sync to local preferences so other parts of the app (PremiumGate, etc.)
        // also see the correct value without another Firestore call.
        await PreferencesService.setPremium(isPremium);
      } catch (_) {
        // Fallback to local cache if Firestore is unreachable
        isPremium = await PreferencesService.isPremium();
      }
    }
    if (mounted) setState(() => _isPremium = isPremium);
  }

  @override
  void initState() {
    super.initState();
    final currentUser = AuthService().currentUser;
    // Try to restore profile pic from local storage first (survives restarts)
    _restoreProfilePic(currentUser);
    _selectedIndex = 0;
    _loadDashboardData();
    // Real-time listener for premium status changes from Firestore
    _startPremiumListener();
    // Load premium status first, then show dialog if needed
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadPremiumStatus();
      if (!mounted) return;
      await _checkPremiumAndShowDialog();
    });
  }

  Future<void> _restoreProfilePic(User? currentUser) async {
    if (currentUser != null && !currentUser.isAnonymous) {
      try {
        final profile = await FirestoreService().getUserProfile();
        if (mounted && profile != null) {
          final pic = profile['profilePic'];
          if (pic != null && pic.toString().isNotEmpty) {
            AuthService.profilePicNotifier.value = pic.toString();
            await PreferencesService.setProfilePicUrl(pic.toString());
            return;
          }
        }
      } catch (e) {
        debugPrint('Failed to restore profile pic: $e');
      }
    }

    final cachedUrl = PreferencesService.cachedProfilePicUrl;
    if (cachedUrl != null && cachedUrl.isNotEmpty && cachedUrl.startsWith('http')) {
      AuthService.profilePicNotifier.value = cachedUrl;
    } else {
      AuthService.profilePicNotifier.value = null;
    }
  }

  void _startPremiumListener() {
    final user = AuthService().currentUser;
    if (user == null || user.isAnonymous) return;
    _profileSub = FirestoreService().userProfileStream.listen((profile) {
      final isPremium = profile?['isPremium'] == true;
      PreferencesService.setPremium(isPremium);
      if (mounted && _isPremium != isPremium) {
        setState(() => _isPremium = isPremium);
      }
    }, onError: (e) => debugPrint('userProfileStream error: $e'));
  }

  void _loadDashboardData() {
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      setState(() {
        final workersList = DummyData.workers;
        _totalWorkersCount = workersList.length;
        int mCount = 0;
        int fCount = 0;
        for (final w in workersList) {
          final genderStr = (w['gender'] ?? '').toString().trim().toLowerCase();
          if (genderStr == 'female') {
            fCount++;
          } else if (genderStr == 'male') {
            mCount++;
          }
        }
        _maleWorkersCount = mCount;
        _femaleWorkersCount = fCount;
        _workersList = List<Map<String, dynamic>>.from(workersList);
        _attendanceDocs = List<Map<String, dynamic>>.from(DummyData.attendance);
        _totalAttendanceCount = DummyData.attendance.length;
        _timeoffDocs = List<Map<String, dynamic>>.from(DummyData.timeoff);
        _totalTimeoffCount = DummyData.timeoff.length;
        _recalculateDummyTotals(_selectedPeriod);
        _holidays = DummyData.holidays.values
            .expand((list) => list)
            .cast<Map<String, dynamic>>()
            .toList();
      });
    } else {
      final firestore = FirestoreService();

      setState(() {
        _holidays = [];
      });

      _holidaysSub = firestore.holidaysStream.listen((snap) {
        if (mounted) {
          setState(() {
            _holidays = snap.docs.map((d) {
              return {...d.data() as Map<String, dynamic>, 'id': d.id};
            }).toList();
          });
        }
      }, onError: (e) => debugPrint('holidaysStream error: $e'));

      _workersSub = firestore.workersStream.listen((snap) {
        if (mounted) {
          int mCount = 0;
          int fCount = 0;
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
            }
          }
          setState(() {
            _workersList = list;
            _totalWorkersCount = snap.docs.length;
            _maleWorkersCount = mCount;
            _femaleWorkersCount = fCount;
          });
        }
      }, onError: (e) => debugPrint('workersStream error: $e'));

      _attendanceSub = firestore.attendanceStream.listen((snap) {
        if (mounted) {
          setState(() {
            _attendanceDocs = snap.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            _totalAttendanceCount = snap.docs.length;
          });
        }
      }, onError: (e) => debugPrint('attendanceStream error: $e'));

      _timeoffSub = firestore.timeoffStream.listen((snap) {
        if (mounted) {
          setState(() {
            _timeoffDocs = snap.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            _totalTimeoffCount = snap.docs.length;
          });
        }
      }, onError: (e) => debugPrint('timeoffStream error: $e'));

      _expensesSub = firestore.expensesStream.listen((snap) {
        if (mounted) {
          setState(() {
            _totalExpensesSum = snap.docs.fold(0.0, (sum, doc) {
              final data = doc.data() as Map<String, dynamic>?;
              return sum + ((data?['amount'] ?? 0.0) as num).toDouble();
            });
          });
        }
      }, onError: (e) => debugPrint('expensesStream error: $e'));

      _payrollSub = firestore.payrollStream.listen((snap) {
        if (mounted) {
          setState(() {
            _totalSalarySum = snap.docs.fold(0.0, (sum, doc) {
              final data = doc.data() as Map<String, dynamic>?;
              if (data == null) return sum;
              final result = PayrollService.calculatePayroll(

                salary: (data['salary'] ?? '').toString(),
                totalWorkDays: (data['totalWorkDays'] ?? '').toString(),
                absents: (data['absents'] ?? '').toString(),
                leaves: (data['leaves'] ?? '').toString(),
                overtimeDays: (data['overtimeDays'] ?? '').toString(),
              );
              return sum + (result['netSalary'] as double);
            });
          });
        }
      }, onError: (e) => debugPrint('payrollStream error: $e'));
    }
  }

  Future<void> _checkPremiumAndShowDialog() async {
    bool isPremium = false;
    final user = AuthService().currentUser;
    if (user != null && !user.isAnonymous) {
      try {
        final profile = await FirestoreService().getUserProfile();
        isPremium = profile?['isPremium'] == true;
      } catch (e) {
        debugPrint('Failed to check premium: $e');
        isPremium = await PreferencesService.isPremium();
      }
    }
    final isGuest = user?.isAnonymous ?? false;
    if (!isPremium && !isGuest && mounted) {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
        builder: (_) => const SubscriptionDialog(),
      );
      // If the user subscribed, refresh premium status to update the sidebar
      if (result == true) {
        await _loadPremiumStatus();
      }
    }
  }

  void _handlePeriodChanged(String period) {
    setState(() {
      _selectedPeriod = period;
      final isGuest = AuthService().currentUser?.isAnonymous ?? false;
      if (isGuest) {
        _recalculateDummyTotals(period);
      }
    });
  }

  void _recalculateDummyTotals(String period) {
    double scale = 1.0;
    if (period == 'Week')
      scale = 0.05;
    else if (period == 'Month')
      scale = 0.2;
    else if (period == '3 Month')
      scale = 0.5;
    else if (period == '6 Month')
      scale = 0.75;
    else if (period == 'Yearly')
      scale = 1.0;

    _totalExpensesSum =
        DummyData.expenses.fold(0.0, (sum, item) {
          return sum + ((item['amount'] ?? 0.0) as num).toDouble();
        }) *
        scale;

    _totalSalarySum =
        DummyData.payroll.fold(0.0, (sum, item) {
          final result = PayrollService.calculatePayroll(
            salary: (item['salary'] ?? '').toString(),
            totalWorkDays: (item['totalWorkDays'] ?? '').toString(),
            absents: (item['absents'] ?? '').toString(),
            leaves: (item['leaves'] ?? '').toString(),
            overtimeDays: (item['overtimeDays'] ?? '').toString(),
          );
          return sum + (result['netSalary'] as double);
        }) *
        scale;
  }

  void _handleLogout() {
    showLogoutDialog(context);
  }

  void _handleBackToLogin() async {
    await AuthService().signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _openProfile() {
    setState(() => _showProfile = true);
  }

  void _navigateToAttendance() {
    setState(() {
      _selectedIndex = 2;
      _selectedSubIndex = 0;
      _showProfile = false;
      _showAssignTimeOff = false;
      _selectedTimeOffWorker = null;
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
                    selectedIndex: _showProfile ? -1 : _selectedIndex,
                    selectedSubIndex: _selectedSubIndex,
                    isGuest: AuthService().currentUser?.isAnonymous ?? false,
                    isPremium: _isPremium,
                    onItemSelected: (index, {subIndex}) => setState(() {
                      _selectedIndex = index;
                      if (subIndex != null) {
                        _selectedSubIndex = subIndex;
                      }
                      _showProfile = false;
                      _showAssignTimeOff = false;
                      _selectedTimeOffWorker = null;
                    }),
                    onBackToLogin: _handleBackToLogin,
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final int stackIndex = _getStackIndex();
                        _activatedScreens[stackIndex] = true;
                        return IndexedStack(
                          index: stackIndex,
                          children: [
                            // 0: Dashboard View
                            _activatedScreens[0]
                                ? TweenAnimationBuilder<double>(
                                    key: ValueKey(stackIndex == 0),
                                    tween: Tween<double>(begin: 0, end: 1),
                                    duration: const Duration(milliseconds: 650),
                                    curve: Curves.easeOutQuart,
                                    builder: (context, value, child) {
                                      return Opacity(
                                        opacity: value,
                                        child: Transform.translate(
                                          offset: Offset(0, 15 * (1 - value)),
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: _buildDashboardView(),
                                  )
                                : const SizedBox.shrink(),
                            // 1: Workers Screen
                            _getScreen(1),
                            // 2: Attendance Screen
                            _getScreen(2),
                            // 3: Payroll Screen
                            _getScreen(3),
                            // 4: Time Off Screen
                            _getScreen(4),
                            // 5: Assets Screen
                            _getScreen(5),
                            // 6: Holidays Screen
                            _getScreen(6),
                            // 7: Expenses Screen
                            _getScreen(7),
                            // 8: Settings Screen
                            _getScreen(8),
                            // 9: Assign Time Off
                            _getScreen(9),
                            // 10: Profile View
                            _activatedScreens[10]
                                ? _buildProfileView()
                                : const SizedBox.shrink(),
                          ],
                        );
                      },
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
          onNotificationTap: _navigateToAttendance,
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
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
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
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SparklineCard(
                          title: 'total_salary'.tr(),
                          amount:
                              '\$${NumberFormat.compact(locale: 'en_US').format(_totalSalarySum.clamp(0, double.infinity))}',
                          rawValue: _totalSalarySum,
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
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
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
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
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
                              attendanceDocs: _attendanceDocs,
                            ),
                          ),
                          const SizedBox(height: 16),
                          LeaveTypesPieChart(
                            period: _selectedPeriod,
                            isEmpty:
                                _totalTimeoffCount == 0 ||
                                _totalWorkersCount == 0,
                            timeoffDocs: _timeoffDocs,
                            workersList: _workersList,
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
                                  attendanceDocs: _attendanceDocs,
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
                                timeoffDocs: _timeoffDocs,
                                workersList: _workersList,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),

                // ==========================================
                // TOP HEADER SECTION (UPCOMING HOLIDAYS)
                // ==========================================
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'upcoming_holidays'.tr(),
                      style: TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    // Period Dropdown Button
                    ValueListenableBuilder<String>(
                      valueListenable: _selectedHolidaysPeriod,
                      builder: (context, period, _) {
                        return CustomTimeframeDropdown(
                          selectedPeriod: period,
                          onChanged: (p) => _selectedHolidaysPeriod.value = p,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ==========================================
                // MAIN WHITE CONTAINER
                // ==========================================
                ValueListenableBuilder<String>(
                  valueListenable: _selectedHolidaysPeriod,
                  builder: (context, holidaysPeriod, _) {
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

                          // Build holiday date from month and day fields
                          final monthStr = (h['month'] ?? '').toString();
                          final dayStr = (h['day'] ?? '').toString();
                          if (monthStr.isEmpty || dayStr.isEmpty) return false;

                          final monthNum = AppDateUtils.parseMonth(monthStr);
                          if (monthNum == null) return false;
                          final dayNum = int.tryParse(dayStr);
                          if (dayNum == null) return false;

                          // Build holiday date (use next year if already passed this year)
                          var holidayDate = DateTime(
                            now.year,
                            monthNum as int,
                            dayNum,
                          );
                          if (holidayDate.isBefore(
                            now.subtract(const Duration(days: 1)),
                          )) {
                            holidayDate = DateTime(
                              now.year + 1,
                              monthNum as int,
                              dayNum,
                            );
                          }

                          final daysUntilHoliday = holidayDate
                              .difference(now)
                              .inDays;
                          if (daysUntilHoliday < 0) return false;

                          switch (holidaysPeriod) {
                            case 'Week':
                              return daysUntilHoliday <= 7;
                            case 'Month':
                              return daysUntilHoliday <= 30;
                            case '3 Month':
                              return daysUntilHoliday <= 90;
                            case '6 Month':
                              return daysUntilHoliday <= 180;
                            case 'Yearly':
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
                          final aDays = int.tryParse(a['remainingDays']?.toString() ?? '') ?? 9999;
                          final bDays = int.tryParse(b['remainingDays']?.toString() ?? '') ?? 9999;
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

  Widget _buildProfileView() {
    return Column(
      children: [
        ProfileInlineHeader(
          onLogout: _handleLogout,
          onNotificationTap: _navigateToAttendance,
        ),
        const Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 40.0, vertical: 30.0),
            child: ProfileBody(),
          ),
        ),
      ],
    );
  }
}

class SidebarWidget extends StatefulWidget {
  final int selectedIndex;
  final int selectedSubIndex;
  final bool isGuest;
  final bool isPremium;
  final void Function(int index, {int? subIndex}) onItemSelected;
  final VoidCallback? onBackToLogin;

  const SidebarWidget({
    super.key,
    required this.selectedIndex,
    this.selectedSubIndex = 0,
    this.isGuest = false,
    this.isPremium = false,
    required this.onItemSelected,
    this.onBackToLogin,
  });

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  bool _isWorkforceExpanded = false;

  @override
  void initState() {
    super.initState();
    _isWorkforceExpanded = widget.selectedIndex == 2;
  }

  @override
  void didUpdateWidget(covariant SidebarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex == 2) {
      _isWorkforceExpanded = true;
    }
  }

  static final _menuItems = [
    ('assets/dashbaord_icon_slidebar.svg', 'sidebar_dashboard', false),
    ('assets/workers_icon_slidebar.svg', 'sidebar_workers', false),
    ('assets/workforce_icon_sldiebar.svg', 'sidebar_workforce', true),
    ('assets/expenses_icon_slidebar.svg', 'sidebar_expenses', false),
    ('assets/settings_icon_slidebar.svg', 'sidebar_settings', false),
  ];

  static final _subItems = [
    ('assets/total_salary.svg', 'sidebar_attendance'),
    ('assets/payroll_icon.svg', 'sidebar_payroll'),
    ('assets/time_off_icon.svg', 'sidebar_time_off'),
    ('assets/assets_icon.svg', 'sidebar_assets'),
    ('assets/holidays_icon.svg', 'sidebar_holidays'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      color: const Color(0xFF0247C4),
      child: Column(
        children: [
          if (!widget.isGuest && !widget.isPremium)
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
                  builder: (context) => const SubscriptionDialog(),
                );
              },
              child: Container(
                width: 238,
                margin: const EdgeInsets.only(top: 29, left: 16, right: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Color(0xFFFFFFFF), width: 1.0),
                  image: const DecorationImage(
                    image: AssetImage('assets/premium_bg.png'),
                    fit: BoxFit.cover,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFFFFFFF).withValues(alpha: 0.55),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Color(0xFF4C84E0).withValues(alpha: 0.25),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        children: [
                          Image.asset(
                            'assets/premium_icon.png',
                            width: 28,
                            height: 28,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'upgrade_pro'.tr(),
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildCheckText('unlock_all_features'.tr()),
                    _buildCheckText('no_commitment'.tr()),
                    _buildCheckText('cancel_anytime'.tr()),
                    const SizedBox(height: 10),
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerRight,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 50,
                          padding: const EdgeInsets.only(left: 16, right: 52),
                          decoration: BoxDecoration(
                            color: Color(0xFF000000),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(
                              color: Color(0xFFFFFFFF),
                              width: 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'get_to_pro'.tr(),
                                maxLines: 1,
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'SF Pro',
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'subscribe_now'.tr(),
                                maxLines: 1,
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'SF Pro',
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: -5,
                          top: -3,
                          bottom: -3,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFFFFF),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Image.asset(
                              "assets/right_back_arrow.png",
                              width: 20,
                              height: 20,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (int i = 0; i < _menuItems.length; i++)
                    if (_menuItems[i].$3)
                      _buildWorkforceItem(i)
                    else
                      _buildMenuItem(
                        _menuItems[i].$1,
                        _menuItems[i].$2.tr(),
                        isSelected: widget.selectedIndex == i,
                        hasDropdown: _menuItems[i].$3,
                        onTap: () {
                          widget.onItemSelected(i);
                        },
                      ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          if (widget.isGuest)
            Container(
              height: 42,
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: GestureDetector(
                onTap: widget.onBackToLogin,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.arrow_back,
                        color: Color(0xFFFFFFFF),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'back_to_login_sidebar'.tr(),
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'SF Pro',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWorkforceItem(int index) {
    if (_isWorkforceExpanded) {
      final isSelected = widget.selectedIndex == index;
      return Stack(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
            decoration: BoxDecoration(
              color: Color(0xFFFFFFFF).withValues(alpha: 0.36),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildWorkforceHeaderItem(
                  onTap: () {
                    setState(() {
                      _isWorkforceExpanded = false;
                    });
                  },
                ),
                const SizedBox(height: 4),
                for (int i = 0; i < _subItems.length; i++)
                  _buildSubMenuItem(
                    _subItems[i].$1,
                    _subItems[i].$2.tr(),
                    isSelected:
                        widget.selectedIndex == index &&
                        widget.selectedSubIndex == i,
                    onTap: () {
                      widget.onItemSelected(index, subIndex: i);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 11.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              width: 8,
              height: isSelected ? 32 : 0,
              decoration: const BoxDecoration(
                color: Color(0xFFFFFFFF),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      return _buildMenuItem(
        _menuItems[index].$1,
        _menuItems[index].$2.tr(),
        isSelected: widget.selectedIndex == index,
        hasDropdown: true,
        onTap: () {
          setState(() {
            _isWorkforceExpanded = true;
          });
          widget.onItemSelected(index);
        },
      );
    }
  }

  Widget _buildWorkforceHeaderItem({VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/workforce_icon_sldiebar.svg',
              height: 22,
              width: 22,
              color: Color(0xFFFFFFFF),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'sidebar_workforce'.tr(),
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'SF Pro',
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              color: Color(0xFFFFFFFF),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMenuItem(
    String iconAsset,
    String title, {
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFFFFF).withValues(alpha: 0.36)
              : const Color(0x00FFFFFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SvgPicture.asset(
              iconAsset,
              height: 20,
              width: 20,
              color: Color(0xFFFFFFFF),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w500,
                  fontFamily: 'SF Pro',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckText(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/tick_icon.svg',
              width: 14,
              height: 10,
              color: Color(0xFFFFFFFF),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    String iconAsset,
    String title, {
    bool isSelected = false,
    bool hasDropdown = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFFFFFFF).withValues(alpha: 0.36)
                  : const Color(0x00FFFFFF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  iconAsset,
                  height: 22,
                  width: 22,
                  color: Color(0xFFFFFFFF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 18,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.w500,
                      fontFamily: 'SF Pro',
                    ),
                  ),
                ),
                if (hasDropdown)
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: Color(0xFFFFFFFF),
                    size: 20,
                  ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                width: 8,
                height: isSelected ? 32 : 0,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TopHeader extends StatelessWidget {
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationTap;
  const TopHeader({
    super.key,
    required this.onProfileTap,
    required this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    final name = user?.displayName ?? 'User';

    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEFF2))),
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Welcome text
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'welcome_user'.tr(namedArgs: {'name': name}),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF000000),
                  fontFamily: 'SF Pro Display',
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'welcome_subtitle'.tr(),
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF000000),
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
          // Right: notification + avatar
          Row(
            children: [
              // Notification bell
              GestureDetector(
                onTap: onNotificationTap,
                child: SvgPicture.asset(
                  'assets/notification_icon.svg',
                  width: 22,
                  height: 26,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF000000),
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Profile avatar (clickable to open profile screen)
              GestureDetector(onTap: onProfileTap, child: const UserAvatar()),
            ],
          ),
        ],
      ),
    );
  }
}

class TotalWorkersCard extends StatelessWidget {
  final int count;
  final int maleCount;
  final int femaleCount;
  const TotalWorkersCard({
    super.key,
    required this.count,
    required this.maleCount,
    required this.femaleCount,
  });

  @override
  Widget build(BuildContext context) {
    final double malePercent = count > 0 ? (maleCount / count) : 0.0;
    final double femalePercent = count > 0 ? (femaleCount / count) : 0.0;
    final String malePercentStr = '${(malePercent * 100).toStringAsFixed(0)}%';
    final String femalePercentStr =
        '${(femalePercent * 100).toStringAsFixed(0)}%';

    return Card(
      elevation: 0,
      color: Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: count > 0
            ? Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SvgPicture.asset(
                              'assets/workers_icon_slidebar.svg',
                              height: 20,
                              width: 20,
                              color: const Color(0xFF155ED5),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'total_workers'.tr(),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '$count',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Expanded(
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          RoundedDonutChart(
                            malePercent: malePercent,
                            femalePercent: femalePercent,
                          ),
                          MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              textScaler: const TextScaler.linear(1.0),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Transform.translate(
                                  offset: const Offset(6, -9),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        malePercentStr,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF000000),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      Text(
                                        'male'.tr(),
                                        style: const TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF000000),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Transform.rotate(
                                  angle: 0.35,
                                  child: Container(
                                    width: 1.0,
                                    height: 52,
                                    color: const Color(0xFF000000),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Transform.translate(
                                  offset: const Offset(-9, 5),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        femalePercentStr,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF000000),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      Text(
                                        'female'.tr(),
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF000000),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildLegendItem(
                          Color(0xFF155ED5),
                          'male'.tr(),
                          'workers_count'.tr(
                            namedArgs: {'count': maleCount.toString()},
                          ),
                        ),
                        _buildLegendItem(
                          Color(0xFFFF2D2D),
                          'female'.tr(),
                          'workers_count'.tr(
                            namedArgs: {'count': femaleCount.toString()},
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/total_workers.svg',
                      height: 40,
                      width: 40,
                      color: const Color(0xFF9CA3AF),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'no_workers_added_yet'.tr(),
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9CA3AF),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String title, String subtitle) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'SF Pro Display',
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF000000),
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class RoundedDonutChart extends StatelessWidget {
  final double malePercent;
  final double femalePercent;

  const RoundedDonutChart({
    super.key,
    required this.malePercent,
    required this.femalePercent,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('$malePercent-$femalePercent'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutQuart,
      builder: (context, value, child) {
        return CustomPaint(
          size: const Size(135, 135),
          painter: _DonutChartPainter(
            progress: value,
            malePercent: malePercent,
            femalePercent: femalePercent,
          ),
        );
      },
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final double progress;
  final double malePercent;
  final double femalePercent;

  _DonutChartPainter({
    this.progress = 1,
    required this.malePercent,
    required this.femalePercent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius =
        (size.width - 24) / 2; // radius to draw the center of the arc

    // Red Paint (Female)
    final redPaint = Paint()
      ..color = const Color(0xFFFF2D2D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Blue Paint (Male)
    final bluePaint = Paint()
      ..color = const Color(0xFF155ED5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Start angle is -45 degrees (-pi / 4)
    const double startAngle = -3.1415926535 / 4;
    final double redSweep = femalePercent * 2 * 3.1415926535;
    final double blueSweep = malePercent * 2 * 3.1415926535;

    // Draw Red first
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      redSweep * progress,
      false,
      redPaint,
    );

    // Draw Blue second (overlaps red caps)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + redSweep * progress,
      blueSweep * progress,
      false,
      bluePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.malePercent != malePercent ||
      oldDelegate.femalePercent != femalePercent;
}

class SparklineCard extends StatelessWidget {
  final String title;
  final String amount;
  final double rawValue;
  final String period;
  final Color lineColor;

  const SparklineCard({
    super.key,
    required this.title,
    required this.amount,
    required this.rawValue,
    required this.period,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = amount == '\$0';
    return Card(
      elevation: 0,
      color: Color(0xFFFFFFFF),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: !isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        flex: 0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: lineColor == const Color(0xFF4C84E0)
                                  ? SvgPicture.asset(
                                      'assets/total_salary.svg',
                                      height: 20,
                                      width: 20,
                                      colorFilter: const ColorFilter.mode(
                                        Color(0xFF155ED5),
                                        BlendMode.srcIn,
                                      ),
                                    )
                                  : Image.asset(
                                      'assets/expense.png',
                                      height: 20,
                                      width: 20,
                                      color: const Color(0xFF155ED5),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
                                  fontFamily: 'SF Pro Display',
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                amount,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  fontFamily: 'SF Pro Display',
                                ),
                                maxLines: 1,
                              ),
                            ),
                            Text(
                              period == 'Month'
                                  ? (title == 'expenses'.tr()
                                        ? 'monthly'.tr().toLowerCase()
                                        : 'month'.tr().toLowerCase())
                                  : (period == 'Week'
                                        ? (title == 'expenses'.tr()
                                              ? 'weekly'.tr().toLowerCase()
                                              : 'week'.tr().toLowerCase())
                                        : CustomTimeframeDropdown.localizePeriod(
                                            period,
                                          )),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black,
                                fontFamily: 'SF Pro Display',
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 90,
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(period),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutQuart,
                    builder: (context, animValue, child) {
                      final double m = period == 'Week'
                          ? 0.3
                          : period == 'Month'
                          ? 0.6
                          : period == '3 Month'
                          ? 0.8
                          : period == '6 Month'
                          ? 0.9
                          : 1.0;
                      final double scaleFactor =
                          (rawValue > 0 ? rawValue : 1.0) / 7.0;
                      final spots = [
                        FlSpot(0, 3 * m * scaleFactor),
                        FlSpot(1, 6 * m * scaleFactor),
                        FlSpot(2, 4 * m * scaleFactor),
                        FlSpot(3, 4 * m * scaleFactor),
                        FlSpot(4, 7 * m * scaleFactor),
                        FlSpot(5, 5 * m * scaleFactor),
                        FlSpot(6, 6 * m * scaleFactor),
                        FlSpot(7, 2 * m * scaleFactor),
                        FlSpot(8, 7 * m * scaleFactor),
                      ];

                      return LineChart(
                        LineChartData(
                          // add horizontal padding so the line doesn't touch card edges
                          minX: -0.5,
                          maxX: (spots.length - 1).toDouble() + 0.5,
                          minY: 0,
                          maxY: 13 * scaleFactor,
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              tooltipRoundedRadius: 8,
                              getTooltipItems: (tSpots) {
                                if (tSpots.isEmpty) return <LineTooltipItem>[];
                                final seenX = <double>{};
                                final nf = NumberFormat.currency(
                                  locale: context.locale.toString(),
                                  symbol: '\$ ',
                                  decimalDigits: 0,
                                );
                                return tSpots.map((tSpot) {
                                  if (seenX.add(tSpot.x)) {
                                    final label = nf.format(tSpot.y);
                                    return LineTooltipItem(
                                      label,
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    );
                                  }
                                  return LineTooltipItem(
                                    '',
                                    const TextStyle(
                                      color: Colors.transparent,
                                      fontSize: 0,
                                    ),
                                  );
                                }).toList();
                              },
                            ),
                          ),
                          gridData: FlGridData(show: false),
                          titlesData: FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots
                                  .map((s) => FlSpot(s.x, s.y * animValue))
                                  .toList(),
                              isCurved: true,
                              color: lineColor.withValues(alpha: 0.06),
                              barWidth: 1.2,
                              isStrokeCapRound: false,
                              dotData: FlDotData(show: false),
                            ),
                            LineChartBarData(
                              spots: spots
                                  .map((s) => FlSpot(s.x, s.y * animValue))
                                  .toList(),
                              isCurved: true,
                              color: lineColor,
                              barWidth: 0.6,
                              isStrokeCapRound: false,
                              dotData: FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  colors: [
                                    lineColor == const Color(0xFF0EA5E9)
                                        ? const Color(
                                            0xFF93D7FD,
                                          ).withValues(alpha: 0.50)
                                        : const Color(
                                            0xFF8DA9F1,
                                          ).withValues(alpha: 0.50),
                                    lineColor == const Color(0xFF0EA5E9)
                                        ? const Color(
                                            0xFF93D7FD,
                                          ).withValues(alpha: 0.20)
                                        : const Color(
                                            0xFF8DA9F1,
                                          ).withValues(alpha: 0.20),
                                    lineColor == const Color(0xFF0EA5E9)
                                        ? const Color(
                                            0xFF93D7FD,
                                          ).withValues(alpha: 0.0)
                                        : const Color(
                                            0xFF8DA9F1,
                                          ).withValues(alpha: 0.0),
                                  ],
                                  stops: [0.0, 0.3, 0.8],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
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
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  lineColor == const Color(0xFF4C84E0)
                      ? SvgPicture.asset(
                          'assets/total_salary.svg',
                          height: 40,
                          width: 40,
                          colorFilter: const ColorFilter.mode(
                            Color(0xFF9CA3AF),
                            BlendMode.srcIn,
                          ),
                        )
                      : Image.asset(
                          'assets/expense.png',
                          height: 40,
                          width: 40,
                          color: const Color(0xFF9CA3AF),
                        ),
                  const SizedBox(height: 8),
                  Text(
                    lineColor == const Color(0xFF4C84E0)
                        ? 'no_salary_records_yet'.tr()
                        : 'no_expenses_recorded_yet'.tr(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9CA3AF),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class ChartData {
  final List<String> labels;
  final List<double> values;
  ChartData(this.labels, this.values);
}

class NiceChartRange {
  final double maxY;
  final double interval;
  NiceChartRange(this.maxY, this.interval);
}

NiceChartRange getNiceRange(double rawMax) {
  if (rawMax <= 0) {
    return NiceChartRange(5, 1);
  }
  if (rawMax <= 5) {
    return NiceChartRange(5, 1);
  } else if (rawMax <= 10) {
    return NiceChartRange(10, 2);
  } else if (rawMax <= 15) {
    return NiceChartRange(15, 3);
  } else if (rawMax <= 20) {
    return NiceChartRange(20, 4);
  } else if (rawMax <= 30) {
    return NiceChartRange(30, 5);
  } else if (rawMax <= 40) {
    return NiceChartRange(40, 8);
  } else if (rawMax <= 50) {
    return NiceChartRange(50, 10);
  } else if (rawMax <= 75) {
    return NiceChartRange(75, 15);
  } else if (rawMax <= 100) {
    return NiceChartRange(100, 20);
  } else if (rawMax <= 150) {
    return NiceChartRange(150, 30);
  } else if (rawMax <= 200) {
    return NiceChartRange(200, 40);
  } else if (rawMax <= 250) {
    return NiceChartRange(250, 50);
  } else if (rawMax <= 300) {
    return NiceChartRange(300, 50);
  } else if (rawMax <= 400) {
    return NiceChartRange(400, 100);
  } else if (rawMax <= 500) {
    return NiceChartRange(500, 100);
  } else if (rawMax <= 600) {
    return NiceChartRange(600, 100);
  } else if (rawMax <= 800) {
    return NiceChartRange(800, 200);
  } else if (rawMax <= 1000) {
    return NiceChartRange(1000, 200);
  } else if (rawMax <= 1500) {
    return NiceChartRange(1500, 300);
  } else if (rawMax <= 2000) {
    return NiceChartRange(2000, 400);
  } else if (rawMax <= 2500) {
    return NiceChartRange(2500, 500);
  } else if (rawMax <= 3000) {
    return NiceChartRange(3000, 500);
  } else if (rawMax <= 4000) {
    return NiceChartRange(4000, 1000);
  } else if (rawMax <= 5000) {
    return NiceChartRange(5000, 1000);
  } else {
    double roughStep = rawMax / 5.0;
    double log10Val = (roughStep.truncate().toString().length - 1).toDouble();
    double power = 1.0;
    for (int i = 0; i < log10Val; i++) {
      power *= 10;
    }
    double normalized = roughStep / power;
    double step;
    if (normalized < 1.5) {
      step = 1.0 * power;
    } else if (normalized < 3.5) {
      step = 2.0 * power;
    } else if (normalized < 7.5) {
      step = 5.0 * power;
    } else {
      step = 10.0 * power;
    }
    double maxY = ((rawMax / step).ceil() * step);
    return NiceChartRange(maxY, step);
  }
}

ChartData getChartData(
  String period,
  List<Map<String, dynamic>> docs,
  bool isGuest,
  String locale,
) {
  final now = DateTime.now();

  if (isGuest || docs.isEmpty) {
    switch (period) {
      case 'Week':
        final labels = <String>[];
        final values = [12.0, 14.0, 8.0, 15.0, 13.0, 11.0, 14.0];
        for (int i = 6; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          labels.add(DateFormat('E', locale).format(date).toUpperCase());
        }
        return ChartData(labels, values);

      case 'Month':
        final labels = [
          'week_label_1'.tr(),
          'week_label_2'.tr(),
          'week_label_3'.tr(),
          'week_label_4'.tr(),
        ];
        final values = [48.0, 55.0, 50.0, 62.0];
        return ChartData(labels, values);

      case '3 Month':
        final labels = <String>[];
        final values = [210.0, 245.0, 230.0];
        for (int i = 2; i >= 0; i--) {
          final date = DateTime(now.year, now.month - i, 1);
          labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
        }
        return ChartData(labels, values);

      case '6 Month':
        final labels = <String>[];
        final values = [420.0, 450.0, 480.0, 510.0, 490.0, 530.0];
        for (int i = 5; i >= 0; i--) {
          final date = DateTime(now.year, now.month - i, 1);
          labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
        }
        return ChartData(labels, values);

      case 'Yearly':
      default:
        final labels = <String>[];
        final dummyValues = [
          95.0,
          120.0,
          240.0,
          330.0,
          290.0,
          510.0,
          960.0,
          850.0,
          910.0,
          980.0,
          1020.0,
          1050.0,
        ];
        final values = <double>[];
        for (int i = 0; i < now.month; i++) {
          final date = DateTime(now.year, i + 1, 1);
          labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
          values.add(dummyValues[i]);
        }
        return ChartData(labels, values);
    }
  }

  final parsedRecords = <DateTime>[];
  for (final doc in docs) {
    final createdAt = doc['createdAt'];
    DateTime? dt;
    if (createdAt is Timestamp) {
      dt = createdAt.toDate();
    } else if (createdAt is String) {
      dt = DateTime.tryParse(createdAt);
    }
    if (dt != null) {
      parsedRecords.add(dt);
    }
  }

  switch (period) {
    case 'Week':
      final labels = <String>[];
      final values = List.filled(7, 0.0);
      final startOfWeek = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 6));

      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        labels.add(DateFormat('E', locale).format(date).toUpperCase());
      }

      for (final dt in parsedRecords) {
        final difference = dt.difference(startOfWeek).inDays;
        if (difference >= 0 && difference < 7) {
          values[difference] += 1.0;
        }
      }
      return ChartData(labels, values);

    case 'Month':
      final labels = [
        'week_label_1'.tr(),
        'week_label_2'.tr(),
        'week_label_3'.tr(),
        'week_label_4'.tr(),
      ];
      final values = List.filled(4, 0.0);
      final startOfPeriod = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 27));

      for (final dt in parsedRecords) {
        final difference = dt.difference(startOfPeriod).inDays;
        if (difference >= 0 && difference < 28) {
          final weekIdx = difference ~/ 7;
          if (weekIdx >= 0 && weekIdx < 4) {
            values[weekIdx] += 1.0;
          }
        }
      }
      return ChartData(labels, values);

    case '3 Month':
      final labels = <String>[];
      final values = List.filled(3, 0.0);

      for (int i = 2; i >= 0; i--) {
        final date = DateTime(now.year, now.month - i, 1);
        labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
      }

      for (final dt in parsedRecords) {
        for (int i = 0; i < 3; i++) {
          final targetDate = DateTime(now.year, now.month - (2 - i), 1);
          if (dt.year == targetDate.year && dt.month == targetDate.month) {
            values[i] += 1.0;
            break;
          }
        }
      }
      return ChartData(labels, values);

    case '6 Month':
      final labels = <String>[];
      final values = List.filled(6, 0.0);

      for (int i = 5; i >= 0; i--) {
        final date = DateTime(now.year, now.month - i, 1);
        labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
      }

      for (final dt in parsedRecords) {
        for (int i = 0; i < 6; i++) {
          final targetDate = DateTime(now.year, now.month - (5 - i), 1);
          if (dt.year == targetDate.year && dt.month == targetDate.month) {
            values[i] += 1.0;
            break;
          }
        }
      }
      return ChartData(labels, values);

    case 'Yearly':
    default:
      final labels = <String>[];
      final values = List.filled(now.month, 0.0);

      for (int i = 0; i < now.month; i++) {
        final date = DateTime(now.year, i + 1, 1);
        labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
      }

      for (final dt in parsedRecords) {
        if (dt.year == now.year && dt.month <= now.month) {
          values[dt.month - 1] += 1.0;
        }
      }
      return ChartData(labels, values);
  }
}

class AttendanceLineChart extends StatelessWidget {
  final String period;
  final bool isEmpty;
  final List<Map<String, dynamic>> attendanceDocs;

  const AttendanceLineChart({
    super.key,
    required this.period,
    this.isEmpty = false,
    this.attendanceDocs = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: !isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    CustomTimeframeDropdown.localizePeriod(period),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 330,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(period),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 750),
                      curve: Curves.easeOutQuart,
                      builder: (context, animValue, child) {
                        final chartData = getChartData(
                          period,
                          attendanceDocs,
                          AuthService().currentUser?.isAnonymous ?? false,
                          context.locale.toString(),
                        );
                        final double rawMaxY = chartData.values.isEmpty
                            ? 1.0
                            : chartData.values.reduce((a, b) => a > b ? a : b);
                        final range = getNiceRange(rawMaxY);
                        final spots = List.generate(
                          chartData.values.length,
                          (i) => FlSpot(i.toDouble(), chartData.values[i]),
                        );

                        return Padding(
                          padding: const EdgeInsets.only(
                            right: 20.0,
                            top: 4.0,
                            bottom: 2.0,
                          ),
                          child: LineChart(
                            LineChartData(
                              // add horizontal padding so the line doesn't touch card edges
                              minX: -0.4,
                              maxX: (spots.length - 1).toDouble() + 0.4,
                              minY: 0,
                              maxY: range.maxY,
                              lineTouchData: LineTouchData(
                                touchTooltipData: LineTouchTooltipData(
                                  getTooltipColor: (spot) =>
                                      const Color(0xFF2C3E50),
                                  tooltipRoundedRadius: 8,
                                  getTooltipItems: (spots) {
                                    return spots.map((spot) {
                                      return LineTooltipItem(
                                        spot.y.toStringAsFixed(0),
                                        const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      );
                                    }).toList();
                                  },
                                ),
                              ),
                              gridData: FlGridData(
                                show: true,
                                drawHorizontalLine: false,
                                drawVerticalLine: true,
                                verticalInterval: 1,
                                checkToShowVerticalLine: (value) {
                                  return (value - value.round()).abs() < 0.01;
                                },
                                getDrawingVerticalLine: (value) => FlLine(
                                  color: Colors.black.withOpacity(0.12),
                                  strokeWidth: 1,
                                ),
                              ),
                              titlesData: FlTitlesData(
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 48,
                                    interval: range.interval,
                                    getTitlesWidget: (value, meta) {
                                      const style = TextStyle(
                                        color: Color(0xFF0247C4),
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'SF Pro Display',
                                      );
                                      if (value < 0 || value > range.maxY) {
                                        return const SizedBox.shrink();
                                      }
                                      return SideTitleWidget(
                                        meta: meta,
                                        space: 0,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              value.toInt().toString(),
                                              style: style,
                                              textAlign: TextAlign.right,
                                              maxLines: 1,
                                              softWrap: false,
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              width: 8,
                                              height: 2,
                                              color: const Color(0xFF939393),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 40,
                                    interval: 1,
                                    getTitlesWidget: (value, meta) {
                                      // Only show titles for integer indices to avoid duplicates at boundary offsets (like -0.5 or 2.5)
                                      if ((value - value.round()).abs() >
                                          0.01) {
                                        return const SizedBox.shrink();
                                      }
                                      final idx = value.round();
                                      if (idx < 0 ||
                                          idx >= chartData.labels.length) {
                                        return const SizedBox.shrink();
                                      }
                                      const style = TextStyle(
                                        color: Color(0xFF0247C4),
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'SF Pro Display',
                                      );
                                      return SideTitleWidget(
                                        meta: meta,
                                        space: 0,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 2,
                                              height: 8,
                                              color: const Color(0xFF939393),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              chartData.labels[idx],
                                              style: style,
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              borderData: FlBorderData(
                                show: true,
                                border: const Border(
                                  bottom: BorderSide(
                                    color: Color(0xFF939393),
                                    width: 1,
                                  ),
                                  left: BorderSide(
                                    color: Color(0xFF939393),
                                    width: 1,
                                  ),
                                ),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: spots
                                      .map((s) => FlSpot(s.x, s.y * animValue))
                                      .toList(),
                                  isCurved: false,
                                  color: const Color(0xFF21367E),
                                  barWidth: 2,
                                  dotData: FlDotData(
                                    show: true,
                                    getDotPainter:
                                        (spot, percent, barData, index) {
                                          return FlDotCirclePainter(
                                            radius: 4,
                                            color: const Color(0xFF21367E),
                                            strokeWidth: 0,
                                          );
                                        },
                                  ),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: const Color(0xFFDEE6FF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              )
            : SizedBox(
                height: 430,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/present_grey.svg',
                        height: 50,
                        width: 50,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'no_attendance_data_yet'.tr(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9CA3AF),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class SlotConfig {
  final double targetAngle;
  final Offset elbow;
  final Offset labelEnd;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;

  const SlotConfig({
    required this.targetAngle,
    required this.elbow,
    required this.labelEnd,
    this.left,
    this.top,
    this.right,
    this.bottom,
  });
}

class LeavePeriodConfig {
  final double casualVal;
  final double sickVal;
  final double medicalVal;

  final List<Offset> casualPath;
  final List<Offset> sickPath;
  final List<Offset> medicalPath;

  final double? casualLeft;
  final double? casualTop;
  final double? casualRight;
  final double? casualBottom;

  final double? sickLeft;
  final double? sickTop;
  final double? sickRight;
  final double? sickBottom;

  final double? medicalLeft;
  final double? medicalTop;
  final double? medicalRight;
  final double? medicalBottom;

  const LeavePeriodConfig({
    required this.casualVal,
    required this.sickVal,
    required this.medicalVal,
    required this.casualPath,
    required this.sickPath,
    required this.medicalPath,
    this.casualLeft,
    this.casualTop,
    this.casualRight,
    this.casualBottom,
    this.sickLeft,
    this.sickTop,
    this.sickRight,
    this.sickBottom,
    this.medicalLeft,
    this.medicalTop,
    this.medicalRight,
    this.medicalBottom,
  });
}

class LeaveTypesPieChart extends StatelessWidget {
  final String period;
  final bool isEmpty;
  final List<Map<String, dynamic>> timeoffDocs;
  final List<Map<String, dynamic>> workersList;

  const LeaveTypesPieChart({
    super.key,
    required this.period,
    this.isEmpty = false,
    required this.timeoffDocs,
    required this.workersList,
  });

  static const Map<String, LeavePeriodConfig> _configs = {
    'Week': LeavePeriodConfig(
      casualVal: 60,
      sickVal: 15,
      medicalVal: 25,
      casualPath: [Offset(147, 116), Offset(97, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(230, 110), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(175, 205), Offset(135, 245), Offset(80, 245)],
      medicalLeft: 90,
      medicalBottom: 18,
    ),
    'Month': LeavePeriodConfig(
      casualVal: 50,
      sickVal: 20,
      medicalVal: 30,
      casualPath: [Offset(151, 107.5), Offset(105, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(226.4, 103.5), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(175, 205), Offset(135, 245), Offset(80, 245)],
      medicalLeft: 90,
      medicalBottom: 18,
    ),
    '3 Month': LeavePeriodConfig(
      casualVal: 45,
      sickVal: 25,
      medicalVal: 30,
      casualPath: [Offset(149, 111), Offset(101, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(222, 98), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(175, 205), Offset(135, 245), Offset(80, 245)],
      medicalLeft: 90,
      medicalBottom: 18,
    ),
    '6 Month': LeavePeriodConfig(
      casualVal: 40,
      sickVal: 30,
      medicalVal: 30,
      casualPath: [Offset(147, 114), Offset(98, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(212, 91), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(175, 205), Offset(135, 245), Offset(80, 245)],
      medicalLeft: 90,
      medicalBottom: 18,
    ),
    'Yearly': LeavePeriodConfig(
      casualVal: 35,
      sickVal: 35,
      medicalVal: 30,
      casualPath: [Offset(146, 118), Offset(95, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(215, 83), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(175, 205), Offset(135, 245), Offset(80, 245)],
      medicalLeft: 90,
      medicalBottom: 18,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final defaultConfig = _configs[period] ?? _configs['Month']!;

    final activeWorkersEmails = workersList
        .map((w) => (w['email'] ?? '').toString().trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    final activeWorkersNames = workersList
        .map((w) => (w['name'] ?? '').toString().trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();

    DateTime? dateLimit;
    final now = DateTime.now();
    if (period == 'Week') {
      dateLimit = now.subtract(const Duration(days: 7));
    } else if (period == 'Month') {
      dateLimit = now.subtract(const Duration(days: 30));
    } else if (period == '3 Month') {
      dateLimit = now.subtract(const Duration(days: 90));
    } else if (period == '6 Month') {
      dateLimit = now.subtract(const Duration(days: 180));
    } else if (period == 'Yearly') {
      dateLimit = now.subtract(const Duration(days: 365));
    }

    int casualCount = 0;
    int sickCount = 0;
    int annualCount = 0;

    for (var t in timeoffDocs) {
      final tEmail = (t['email'] ?? '').toString().trim().toLowerCase();
      final tName = (t['name'] ?? '').toString().trim().toLowerCase();
      final belongsToActive =
          (tEmail.isNotEmpty && activeWorkersEmails.contains(tEmail)) ||
          (tName.isNotEmpty && activeWorkersNames.contains(tName));
      if (!belongsToActive) continue;

      if (dateLimit != null) {
        final tDate = DateTime.tryParse(t['startDate'] ?? '');
        if (tDate != null && tDate.isBefore(dateLimit)) {
          continue;
        }
      }

      final action = (t['action'] ?? '').toString().trim().toLowerCase();
      if (action.contains('casual')) {
        casualCount++;
      } else if (action.contains('sick')) {
        sickCount++;
      } else if (action.contains('annual') || action.contains('maternity')) {
        annualCount++;
      } else {
        annualCount++;
      }
    }

    final int total = casualCount + sickCount + annualCount;
    final double casualPercent = total > 0 ? (casualCount / total) * 100 : 0.0;
    final double sickPercent = total > 0 ? (sickCount / total) * 100 : 0.0;
    final double medicalPercent = total > 0 ? (annualCount / total) * 100 : 0.0;

    final double casualVal = total > 0
        ? casualPercent
        : defaultConfig.casualVal;
    final double sickVal = total > 0 ? sickPercent : defaultConfig.sickVal;
    final double medicalVal = total > 0
        ? medicalPercent
        : defaultConfig.medicalVal;

    final double totalValue = casualVal + sickVal + medicalVal;
    final double casualSweep = totalValue > 0
        ? (casualVal / totalValue) * 360
        : 0;
    final double sickSweep = totalValue > 0 ? (sickVal / totalValue) * 360 : 0;
    final double medicalSweep = totalValue > 0
        ? (medicalVal / totalValue) * 360
        : 0;

    double normalizeAngle(double a) {
      double val = a % 360;
      if (val < 0) val += 360;
      return val;
    }

    final double aCasual = normalizeAngle(108 + casualSweep / 2);
    final double aSick = normalizeAngle(108 + casualSweep + sickSweep / 2);
    final double aMedical = normalizeAngle(
      108 + casualSweep + sickSweep + medicalSweep / 2,
    );

    double angleDistance(double a, double b) {
      double diff = (a - b).abs() % 360;
      return diff > 180 ? 360 - diff : diff;
    }

    final slots = [
      const SlotConfig(
        targetAngle: 0.0, // Top-Right
        elbow: Offset(275, 60),
        labelEnd: Offset(325, 60),
        right: 65,
        top: 36,
      ),
      const SlotConfig(
        targetAngle: 120.0, // Bottom-Left
        elbow: Offset(135, 245),
        labelEnd: Offset(80, 245),
        left: 90,
        bottom: 18,
      ),
      const SlotConfig(
        targetAngle: 240.0, // Top-Left
        elbow: Offset(105, 60),
        labelEnd: Offset(55, 60),
        left: 65,
        top: 36,
      ),
    ];

    final sliceAngles = [aCasual, aSick, aMedical];
    final permutations = const [
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0],
    ];

    double minCost = double.infinity;
    List<int> bestPerm = permutations[0];

    for (final perm in permutations) {
      double cost = 0;
      for (int i = 0; i < 3; i++) {
        cost += angleDistance(sliceAngles[i], slots[perm[i]].targetAngle);
      }
      if (cost < minCost) {
        minCost = cost;
        bestPerm = perm;
      }
    }

    final slotCasual = slots[bestPerm[0]];
    final slotSick = slots[bestPerm[1]];
    final slotMedical = slots[bestPerm[2]];

    double getClosestAngleInSlice(
      double startAngle,
      double endAngle,
      double targetAngle,
      double padding,
    ) {
      double sweep = endAngle - startAngle;
      if (sweep < 0) sweep += 360;

      if (sweep <= 2 * padding) {
        return normalizeAngle(startAngle + sweep / 2);
      }

      double startLimit = startAngle + padding;
      double endLimit = startAngle + sweep - padding;

      double t = (targetAngle - startLimit) % 360;
      if (t < 0) t += 360;

      double allowedSweep = endLimit - startLimit;

      if (t <= allowedSweep) {
        return normalizeAngle(startLimit + t);
      } else {
        double distToStart = 360 - t;
        double distToEnd = t - allowedSweep;
        if (distToStart < distToEnd) {
          return normalizeAngle(startLimit);
        } else {
          return normalizeAngle(endLimit);
        }
      }
    }

    // Slice 1: Casual
    final double casualStartAngle = 108;
    final double casualEndAngle = 108 + casualSweep;
    final double casualLineAngle = getClosestAngleInSlice(
      casualStartAngle,
      casualEndAngle,
      slotCasual.targetAngle,
      casualSweep * 0.35,
    );

    // Slice 2: Sick
    final double sickStartAngle = casualEndAngle;
    final double sickEndAngle = casualEndAngle + sickSweep;
    final double sickLineAngle = getClosestAngleInSlice(
      sickStartAngle,
      sickEndAngle,
      slotSick.targetAngle,
      sickSweep * 0.35,
    );

    // Slice 3: Medical
    final double medicalStartAngle = sickEndAngle;
    final double medicalEndAngle = sickEndAngle + medicalSweep;
    final double medicalLineAngle = getClosestAngleInSlice(
      medicalStartAngle,
      medicalEndAngle,
      slotMedical.targetAngle,
      medicalSweep * 0.35,
    );

    Offset getCircumferencePoint(double angleDegrees) {
      final double rad = angleDegrees * math.pi / 180;
      return Offset(190 + 45 * math.cos(rad), 130 + 45 * math.sin(rad));
    }

    final config = LeavePeriodConfig(
      casualVal: casualVal,
      sickVal: sickVal,
      medicalVal: medicalVal,
      casualPath: [
        getCircumferencePoint(casualLineAngle),
        slotCasual.elbow,
        slotCasual.labelEnd,
      ],
      sickPath: [
        getCircumferencePoint(sickLineAngle),
        slotSick.elbow,
        slotSick.labelEnd,
      ],
      medicalPath: [
        getCircumferencePoint(medicalLineAngle),
        slotMedical.elbow,
        slotMedical.labelEnd,
      ],
      casualLeft: slotCasual.left,
      casualTop: slotCasual.top,
      casualRight: slotCasual.right,
      casualBottom: slotCasual.bottom,
      sickLeft: slotSick.left,
      sickTop: slotSick.top,
      sickRight: slotSick.right,
      sickBottom: slotSick.bottom,
      medicalLeft: slotMedical.left,
      medicalTop: slotMedical.top,
      medicalRight: slotMedical.right,
      medicalBottom: slotMedical.bottom,
    );

    final bool reallyEmpty = isEmpty || total == 0 || workersList.isEmpty;

    return Card(
      elevation: 0,
      color: const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: !reallyEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    CustomTimeframeDropdown.localizePeriod(period),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: SizedBox(
                      width: 380,
                      height: 260,
                      child: TweenAnimationBuilder<double>(
                        key: const ValueKey('entrance'),
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutQuart,
                        builder: (context, value, childWidget) {
                          return Opacity(opacity: value, child: childWidget);
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          switchInCurve: Curves.easeInOutCubic,
                          switchOutCurve: Curves.easeInOutCubic,
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                          child: Stack(
                            key: ValueKey(period),
                            alignment: Alignment.center,
                            children: [
                              PieChart(
                                PieChartData(
                                  sectionsSpace: 0.0,
                                  centerSpaceRadius: 0,
                                  startDegreeOffset: 108,
                                  sections: [
                                    PieChartSectionData(
                                      color: const Color(
                                        0xFF84A9FF,
                                      ), // Casual Leave
                                      value: config.casualVal,
                                      radius: 85,
                                      showTitle: false,
                                    ),
                                    PieChartSectionData(
                                      color: const Color(
                                        0xFFFF4A5E,
                                      ), // Sick Leave
                                      value: config.sickVal,
                                      radius: 85,
                                      showTitle: false,
                                    ),
                                    PieChartSectionData(
                                      color: const Color(
                                        0xFF97FFA9,
                                      ), // Medical Leave
                                      value: config.medicalVal,
                                      radius: 85,
                                      showTitle: false,
                                    ),
                                  ],
                                ),
                              ),
                              CustomPaint(
                                size: const Size(380, 260),
                                painter: CalloutLinesPainter(
                                  casualPath: config.casualVal > 0
                                      ? config.casualPath
                                      : const [],
                                  sickPath: config.sickVal > 0
                                      ? config.sickPath
                                      : const [],
                                  medicalPath: config.medicalVal > 0
                                      ? config.medicalPath
                                      : const [],
                                ),
                              ),
                              if (config.casualVal > 0)
                                Positioned(
                                  top: config.casualTop,
                                  left: config.casualLeft,
                                  right: config.casualRight,
                                  bottom: config.casualBottom,
                                  child: _ChartLabel(
                                    '${config.casualVal.toInt()}%',
                                  ),
                                ),
                              if (config.sickVal > 0)
                                Positioned(
                                  top: config.sickTop,
                                  left: config.sickLeft,
                                  right: config.sickRight,
                                  bottom: config.sickBottom,
                                  child: _ChartLabel(
                                    '${config.sickVal.toInt()}%',
                                  ),
                                ),
                              if (config.medicalVal > 0)
                                Positioned(
                                  top: config.medicalTop,
                                  left: config.medicalLeft,
                                  right: config.medicalRight,
                                  bottom: config.medicalBottom,
                                  child: _ChartLabel(
                                    '${config.medicalVal.toInt()}%',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildLegendItem(
                                const Color(0xFF84A9FF),
                                'casual_leave'.tr(
                                  namedArgs: {
                                    'value': '${config.casualVal.toInt()}',
                                  },
                                ),
                              ),
                            ),
                            Expanded(
                              child: _buildLegendItem(
                                const Color(0xFFFF4A5E),
                                'sick_leave'.tr(
                                  namedArgs: {
                                    'value': '${config.sickVal.toInt()}',
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildLegendItem(
                                const Color(0xFF97FFA9),
                                'medical_leave'.tr(
                                  namedArgs: {
                                    'value': '${config.medicalVal.toInt()}',
                                  },
                                ),
                              ),
                            ),
                            const Expanded(child: SizedBox()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : SizedBox(
                height: 430,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/leave_grey.svg',
                        height: 50,
                        width: 50,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'no_leave_data_yet'.tr(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9CA3AF),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF000000),
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
      ],
    );
  }
}

class _ChartLabel extends StatelessWidget {
  final String text;
  const _ChartLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Color(0xFF000000),
        fontFamily: 'SF Pro Display',
      ),
    );
  }
}

class CalloutLinesPainter extends CustomPainter {
  final List<Offset> casualPath;
  final List<Offset> sickPath;
  final List<Offset> medicalPath;

  CalloutLinesPainter({
    required this.casualPath,
    required this.sickPath,
    required this.medicalPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    _drawOffsetPath(canvas, paint, casualPath);
    _drawOffsetPath(canvas, paint, sickPath);
    _drawOffsetPath(canvas, paint, medicalPath);
  }

  void _drawOffsetPath(Canvas canvas, Paint paint, List<Offset> points) {
    if (points.length < 2) return;
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CalloutLinesPainter oldDelegate) {
    return oldDelegate.casualPath != casualPath ||
        oldDelegate.sickPath != sickPath ||
        oldDelegate.medicalPath != medicalPath;
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

// ==========================================
// REUSABLE CUSTOM HOLIDAY CARD WIDGET
// ==========================================
class HolidayCard extends StatelessWidget {
  final String day;
  final String month;
  final String remainingDays;
  final String dayOfWeek;
  final String holidayName;
  final bool isActive;

  const HolidayCard({
    super.key,
    required this.day,
    required this.month,
    required this.remainingDays,
    required this.dayOfWeek,
    required this.holidayName,
    this.isActive = false,
  });

  static String _localizeMonth(String month) {
    switch (month) {
      case 'January':
        return 'month_january'.tr();
      case 'February':
        return 'month_february'.tr();
      case 'March':
        return 'month_march'.tr();
      case 'April':
        return 'month_april'.tr();
      case 'May':
        return 'month_may'.tr();
      case 'June':
        return 'month_june'.tr();
      case 'July':
        return 'month_july'.tr();
      case 'August':
        return 'month_august'.tr();
      case 'September':
        return 'month_september'.tr();
      case 'October':
        return 'month_october'.tr();
      case 'November':
        return 'month_november'.tr();
      case 'December':
        return 'month_december'.tr();
      default:
        return month;
    }
  }

  static String _localizeDayOfWeek(String day) {
    switch (day) {
      case 'Monday':
        return 'weekday_monday'.tr();
      case 'Tuesday':
        return 'weekday_tuesday'.tr();
      case 'Wednesday':
        return 'weekday_wednesday'.tr();
      case 'Thursday':
        return 'weekday_thursday'.tr();
      case 'Friday':
        return 'weekday_friday'.tr();
      case 'Saturday':
        return 'weekday_saturday'.tr();
      case 'Sunday':
        return 'weekday_sunday'.tr();
      default:
        return day;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Define exact colors based on state

    // Active (Red) State Colors
    final Color activeLeftBg = const Color(0xFFFF5F65); // #FF5F65 left bg
    final Color activeRightBg = const Color(0xFFFF000A); // #FF000A right bg
    final Color activeTextColor = Color(0xFFFFFFFF);
    final Color activeSubTextColor = Color(0xFFFFFFFF).withValues(alpha: 0.9);
    final Color activeBadgeBg = const Color(0xFFFF5F65); // Matches left bg

    // Inactive (Grey) State Colors
    final Color inactiveLeftBg = const Color(0xFFE2E4E4); // Darker grey left
    final Color inactiveRightBg = const Color(0xFFF1F1F1); // Lighter grey right
    final Color inactiveTextColor = Color(0xFF000000);
    final Color inactiveSubTextColor = Colors.black;
    final Color inactiveBadgeBg = const Color(0xFF4C84E0); // Blue badge

    // Assign chosen colors
    Color leftBg = isActive ? activeLeftBg : inactiveLeftBg;
    Color rightBg = isActive ? activeRightBg : inactiveRightBg;
    Color mainTextColor = isActive ? activeTextColor : inactiveTextColor;
    Color subTextColor = isActive ? activeSubTextColor : inactiveSubTextColor;
    Color badgeBg = isActive ? activeBadgeBg : inactiveBadgeBg;

    return Container(
      height: 115,
      clipBehavior: Clip.antiAlias, // Ensures corners clip contents
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          // --- Left Side (Date) ---
          Container(
            width: 50, // Reduced from 55 to give more horizontal room for text
            color: leftBg,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  day,
                  style: TextStyle(
                    color: mainTextColor,
                    fontSize: 18, // Reduced from 20
                    fontWeight: FontWeight.w700,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _localizeMonth(month),
                  style: TextStyle(
                    color: mainTextColor,
                    fontSize: 12, // Reduced from 14
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ],
            ),
          ),

          // --- Right Side (Details) ---
          Expanded(
            child: Container(
              color: rightBg,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // Top Row: Remaining Days
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'remaining_days'.tr(),
                          style: TextStyle(
                            color: subTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'SF Pro Display',
                            height: 1.0,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 30,
                        child: Text(
                          remainingDays,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.visible,
                          style: TextStyle(
                            color: mainTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'SF Pro Display',
                            height: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const SizedBox(height: 2),
                  // Middle: Day Pill Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _localizeDayOfWeek(dayOfWeek),
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Bottom: Holiday Name
                  Text(
                    holidayName,
                    maxLines: 2,
                    style: TextStyle(
                      color: mainTextColor,
                      fontSize: 13,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
